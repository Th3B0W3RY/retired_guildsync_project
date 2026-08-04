# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Discord Bot Authorization Flow", type: :request do
  let(:user) { create(:user, :with_mfa) }
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:subscription) { create(:subscription, user: user, pricing_plan: pricing_plan) }
  let(:guild) { create(:guild, owner: user) }
  # Owner membership is automatically created by guild factory

  # Discord test data
  let(:development_server_id) { ENV["DISCORD_GUILDSYNC_DEVELOPMENT_SERVER_ID"] || "123456789012345678" }
  let(:fake_discord_user_id) { "987654321098765432" }
  let(:fake_discord_username) { "TestUser#1234" }
  let(:fake_access_token) { "fake_access_token_12345" }
  let(:fake_refresh_token) { "fake_refresh_token_67890" }
  let(:fake_oauth_code) { "fake_oauth_code_abc123" }
  let(:fake_oauth_state) { SecureRandom.hex(16) }

  let(:fake_token_response) do
    {
      "access_token" => fake_access_token,
      "refresh_token" => fake_refresh_token,
      "expires_in" => 604800,
      "token_type" => "Bearer"
    }
  end

  let(:fake_user_info) do
    {
      "id" => fake_discord_user_id,
      "username" => fake_discord_username.split("#").first,
      "discriminator" => fake_discord_username.split("#").last
    }
  end

  let(:fake_discord_guilds) do
    [
      {
        "id" => development_server_id,
        "name" => "GuildSync DEVELOPMENT",
        "owner" => true,
        "permissions" => "0x8"
      }
    ]
  end

  let(:fake_guild_info) do
    {
      "id" => development_server_id,
      "name" => "GuildSync DEVELOPMENT",
      "icon" => nil
    }
  end

  before do
    # Set environment variable for development server ID first
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_GUILDSYNC_DEVELOPMENT_SERVER_ID").and_return(development_server_id)
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_ID").and_return("test_client_id")
    allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("test_bot_token")

    # Stub Discord API calls using allow_any_instance_of for flexibility
    allow_any_instance_of(DiscordService).to receive(:exchange_code_for_token).and_return(fake_token_response)
    allow_any_instance_of(DiscordService).to receive(:get_user_info).and_return(fake_user_info)
    allow_any_instance_of(DiscordService).to receive(:get_user_guilds).and_return(fake_discord_guilds)
    allow_any_instance_of(DiscordService).to receive(:get_guild).and_return(fake_guild_info)

    # Stub authorization_url - user OAuth uses only identify + guilds (no bot)
    allow_any_instance_of(DiscordService).to receive(:authorization_url) do |instance, redirect_uri, state, guild_id: nil, for_bot: false|
      client_id = ENV["DISCORD_CLIENT_ID"]
      
      if for_bot
        scopes = "identify guilds bot applications.commands"
        permissions = 8
        target_guild_id = guild_id || ENV["DISCORD_GUILDSYNC_DEVELOPMENT_SERVER_ID"]
      else
        scopes = "identify guilds"
        permissions = nil
        target_guild_id = nil
      end

      params = {
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: scopes,
        state: state
      }
      
      if for_bot
        params[:permissions] = permissions
        params[:guild_id] = target_guild_id if target_guild_id.present?
      end

      query_string = params.compact.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
      "https://discord.com/api/oauth2/authorize?#{query_string}"
    end

    # Bypass MFA verification for tests
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:require_mfa_if_enabled).and_return(true)

    sign_in user
  end

  describe "Complete Bot Authorization Flow" do
    context "when user selects server and authorizes bot" do
      it "completes the full workflow: user OAuth popup → server selection → bot auth popup → authorize → popup closes" do
        # Step 1: Connect Discord account (user OAuth popup)
        unless user.user_discord_connection.present?
          get new_guild_discord_connection_path(guild), params: { popup: true }
          oauth_state = session[:discord_oauth_state]

          get discord_oauth_callback_path, params: {
            code: fake_oauth_code,
            state: oauth_state
          }

          # Should render HTML that sends message to opener (not redirect)
          expect(response).to have_http_status(:success)
          expect(response.body).to include("DISCORD_USER_CONNECTED")
          expect(UserDiscordConnection.count).to eq(1)
        end

        # Step 2: Server selection page (main window, not popup)
        selected_server_id = "987654321098765432"
        selected_server_name = "My Test Server"

        fake_selected_guild = {
          "id" => selected_server_id,
          "name" => selected_server_name,
          "owner" => true
        }
        allow_any_instance_of(DiscordService).to receive(:get_user_guilds).and_return([ fake_selected_guild ])
        allow(RestClient).to receive(:get).and_return(double(code: 200))

        get select_discord_server_path(guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(selected_server_name)

        # Step 3: Connect server (AJAX request returns bot_auth_url)
        post connect_discord_server_path(guild), params: {
          discord_guild_id: selected_server_id
        }, headers: { 'Accept' => 'application/json', 'X-Requested-With' => 'XMLHttpRequest' }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['bot_auth_url']).to be_present
        expect(json_response['bot_auth_url']).to include("guild_id=#{selected_server_id}")
        expect(json_response['bot_auth_url']).to include("disable_guild_select=true")

        # Verify guild Discord setting was created
        guild.reload
        discord_setting = guild.guild_discord_setting
        expect(discord_setting).to be_present
        expect(discord_setting.discord_guild_id).to eq(selected_server_id)
        expect(discord_setting.discord_guild_name).to eq(selected_server_name)
        expect(session[:bot_auth_guild_id]).to eq(guild.id)

        # Step 4: Bot authorization callback (simulate Discord redirect)
        bot_code = "bot_oauth_code_123"
        allow(RestClient).to receive(:post).and_return(double(
          body: { access_token: "bot_token" }.to_json,
          code: 200
        ))

        get discord_oauth_callback_path, params: { code: bot_code }

        # Should render styled HTML that sends message to opener
        expect(response).to have_http_status(:success)
        expect(response.body).to include("GuildSync bot authorized successfully!")
        expect(response.body).to include("DISCORD_BOT_AUTHORIZED")
        expect(response.body).to include("window.close()")

        # Verify connected_at was updated
        expect(guild.reload.guild_discord_setting.connected_at).to be_present
      end
    end

    context "when user authorization URL is generated" do
      it "uses only identify + guilds scopes (no bot permissions)" do
        service = DiscordService.new
        url = service.authorization_url("http://localhost:5000/callback", "test_state", for_bot: false)

        expect(url).to include("scope=identify+guilds")
        expect(url).not_to include("bot")
        expect(url).not_to include("permissions")
        expect(url).not_to include("guild_id")
      end
    end

    context "when bot authorization URL is generated" do
      it "includes bot scopes, permissions, and guild_id" do
        service = DiscordService.new
        url = service.authorization_url("http://localhost:5000/callback", "test_state", guild_id: development_server_id, for_bot: true)

        expect(url).to include("scope=identify+guilds+bot+applications.commands")
        expect(url).to include("permissions=8")
        expect(url).to include("guild_id=#{development_server_id}")
      end
    end

    context "when bot invite URL is generated" do
      it "uses the SELECTED server's ID (not a hardcoded one)" do
        selected_server_id = "111222333444555666"
        selected_server_name = "My Selected Server"

        discord_setting = create(:guild_discord_setting,
          guild: guild,
          discord_guild_id: selected_server_id,
          discord_guild_name: selected_server_name
        )

        # Ensure user has a valid Discord connection so the bot invite banner
        # is rendered on the connection page.
        create(:user_discord_connection,
               user: user,
               discord_user_id: fake_discord_user_id,
               access_token: fake_access_token,
               refresh_token: fake_refresh_token,
               expires_at: 1.hour.from_now)

        # Mock bot not connected
        error_response = double(code: 404, body: '{"message": "Unknown Guild"}')
        not_found_error = RestClient::NotFound.new(error_response)
        allow_any_instance_of(DiscordService).to receive(:get_guild).and_raise(not_found_error)

        get guild_connect_discord_path(guild)

        # Bot invite URL should use the SELECTED server's ID, not a hardcoded one
        expect(response.body).to include("guild_id=#{selected_server_id}")
        expect(response.body).not_to include("guild_id=#{development_server_id}") unless selected_server_id == development_server_id
      end
    end

    context "when bot presence check job runs" do
      it "verifies bot is in GuildSync DEVELOPMENT server" do
        # Create a guild with Discord setting pointing to DEVELOPMENT server
        discord_setting = create(:guild_discord_setting,
          guild: guild,
          discord_guild_id: development_server_id,
          discord_guild_name: "GuildSync DEVELOPMENT"
        )

        # Mock successful bot presence check - the before block already stubs get_guild
        # Run the job
        result = DiscordBotPresenceCheckJob.new.perform

        expect(result).to be true

        # Verify connected_at was updated
        discord_setting.reload
        expect(discord_setting.connected_at).to be_within(1.second).of(Time.current)
      end

      it "handles bot not being in server gracefully" do
        discord_setting = create(:guild_discord_setting,
          guild: guild,
          discord_guild_id: development_server_id,
          discord_guild_name: "GuildSync DEVELOPMENT"
        )

        # Override the stub for this specific test to raise 404
        error_response = double(code: 404, body: '{"message": "Unknown Guild"}')
        not_found_error = RestClient::NotFound.new(error_response)
        allow_any_instance_of(DiscordService).to receive(:get_guild).and_raise(not_found_error)

        # Run the job
        result = DiscordBotPresenceCheckJob.new.perform

        expect(result).to be false
      end
    end

    context "popup flow - select server then auto-authorize bot" do
      it "selects server → AJAX returns bot_auth_url → bot auth popup opens → popup closes after authorization" do
        # Ensure user has Discord connection
        unless user.user_discord_connection.present?
          get new_guild_discord_connection_path(guild), params: { popup: true }
          oauth_state = session[:discord_oauth_state]

          get discord_oauth_callback_path, params: {
            code: fake_oauth_code,
            state: oauth_state
          }

          expect(response).to have_http_status(:success)
          expect(response.body).to include("DISCORD_USER_CONNECTED")
        end

        # Step 1: User selects a server from the list (in main window)
        selected_server_id = "555666777888999000"
        selected_server_name = "Selected Test Server"

        fake_selected_guild = {
          "id" => selected_server_id,
          "name" => selected_server_name,
          "owner" => true
        }
        allow_any_instance_of(DiscordService).to receive(:get_user_guilds).and_return([ fake_selected_guild ])
        allow(RestClient).to receive(:get).and_return(double(code: 200))

        # Step 2: Connect server (AJAX request)
        post connect_discord_server_path(guild), params: {
          discord_guild_id: selected_server_id
        }, headers: { 'Accept' => 'application/json', 'X-Requested-With' => 'XMLHttpRequest' }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['bot_auth_url']).to be_present
        expect(json_response['bot_auth_url']).to include("guild_id=#{selected_server_id}")

        # Verify server was saved
        guild.reload
        expect(guild.guild_discord_setting.discord_guild_id).to eq(selected_server_id)
        expect(session[:bot_auth_guild_id]).to eq(guild.id)

        # Step 3: Bot authorization callback (simulate)
        bot_code = "bot_oauth_code_456"
        allow(RestClient).to receive(:post).and_return(double(
          body: { access_token: "bot_token" }.to_json,
          code: 200
        ))

        get discord_oauth_callback_path, params: { code: bot_code }

        # Should render styled HTML that closes popup
        expect(response).to have_http_status(:success)
        expect(response.body).to include("GuildSync bot authorized successfully!")
        expect(response.body).to include("DISCORD_BOT_AUTHORIZED")
        expect(response.body).to include("window.close()")

        # Verify connected_at was updated
        expect(guild.reload.guild_discord_setting.connected_at).to be_present
      end
    end

    context "bot OAuth callback re-checks can_manage_discord_channels" do
      let(:guild_owner) { create(:user, :with_mfa) }
      let!(:guild_owner_subscription) { create(:subscription, user: guild_owner, pricing_plan: pricing_plan) }
      let(:guild) { create(:guild, owner: guild_owner) }
      let(:perm_slot) { "discord-bot-oauth-recheck-slot" }
      let(:officer) do
        u = build(:user, skip_free_plan_subscription: true, auth_method: "discord")
        u.save!
        create(:subscription, user: u, pricing_plan: pricing_plan) unless u.subscriptions.any?
        u
      end

      before do
        create(:guild_member, guild: guild, user: officer, role: :member, status: :active,
          discord_role_id: perm_slot)
        guild.update!(permission_role_1_id: perm_slot, role_1_can_manage_discord_channels: true)
        create(:user_discord_connection,
          user: officer,
          discord_user_id: fake_discord_user_id,
          access_token: fake_access_token,
          refresh_token: fake_refresh_token,
          expires_at: 1.hour.from_now)
        sign_in officer
      end

      it "does not exchange bot code when permission is revoked before callback" do
        selected_server_id = "999888777666555444"
        selected_server_name = "Recheck Server"
        fake_selected = {
          "id" => selected_server_id,
          "name" => selected_server_name,
          "owner" => true,
          "permissions" => "0x8"
        }
        allow_any_instance_of(DiscordService).to receive(:get_user_guilds).and_return([ fake_selected ])
        allow(RestClient).to receive(:get).and_return(double(code: 200))

        post connect_discord_server_path(guild), params: { discord_guild_id: selected_server_id },
          headers: { "Accept" => "application/json", "X-Requested-With" => "XMLHttpRequest" }

        expect(response).to have_http_status(:success)
        expect(session[:bot_auth_guild_id]).to eq(guild.id)

        guild.update!(role_1_can_manage_discord_channels: false)

        expect(RestClient).not_to receive(:post)
        get discord_oauth_callback_path, params: { code: "bot_revoked_perm_code" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include(I18n.t("controllers.guilds.permissions.discord_channels_denied"))
        expect(response.body).not_to include("DISCORD_BOT_AUTHORIZED")
        expect(guild.reload.guild_discord_setting.connected_at).to be_nil
      end
    end
  end
end
