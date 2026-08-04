# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Discord Bot Join Service", type: :service do
  let(:guild_id) { "1442060923442561087" }
  let(:client_id) { "1441181242845560833" }
  let(:redirect_uri) { "http://localhost:5000/discord/oauth/callback" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_BOT_CLIENT_ID").and_return(client_id)
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_ID").and_return(client_id)
  end

  describe "Bot authorization URL generation" do
    let(:controller) { DiscordConnectionsController.new }
    
    before do
      request = ActionDispatch::TestRequest.create('HTTP_HOST' => 'localhost:5000', 'rack.url_scheme' => 'http')
      controller.request = request
      controller.instance_variable_set(:@guild, Guild.new(id: 1))
    end

    it "generates URL with correct format" do
      url = controller.send(:bot_authorization_url, guild_id)
      
      expect(url).to start_with("https://discord.com/oauth2/authorize?")
      expect(url).to include("client_id=#{client_id}")
      expect(url).to include("scope=bot+applications.commands")
      expect(url).to include("permissions=8")
      expect(url).to include("guild_id=#{guild_id}")
      expect(url).to include("disable_guild_select=true")
      expect(url).to include("response_type=code")
      expect(url).to include("redirect_uri=#{CGI.escape(redirect_uri)}")
    end

    it "does not include state parameter" do
      url = controller.send(:bot_authorization_url, guild_id)
      
      expect(url).not_to include("state=")
    end

    it "matches working URL format exactly" do
      url = controller.send(:bot_authorization_url, guild_id)
      working_url = "https://discord.com/oauth2/authorize?client_id=#{client_id}&scope=bot+applications.commands&permissions=8&guild_id=#{guild_id}&disable_guild_select=true&response_type=code&redirect_uri=#{CGI.escape(redirect_uri)}"
      
      # Parse and compare parameters
      require 'uri'
      url_params = URI.decode_www_form(URI.parse(url).query).to_h
      working_params = URI.decode_www_form(URI.parse(working_url).query).to_h
      
      expect(url_params).to eq(working_params)
    end
  end

  describe "Bot callback handling" do
    let(:guild) { create(:guild) }
    let(:code) { "test_oauth_code" }
    let(:controller) { DiscordConnectionsController.new }

    before do
      request = ActionDispatch::TestRequest.create('HTTP_HOST' => 'localhost:5000', 'rack.url_scheme' => 'http')
      response = ActionDispatch::TestResponse.new
      controller.request = request
      controller.instance_variable_set(:@_response, response)
      controller.params = ActionController::Parameters.new(code: code)
      allow(controller).to receive(:current_user).and_return(guild.owner)

      # Stub token exchange
      stub_request(:post, "https://discord.com/api/oauth2/token")
        .to_return(status: 200, body: { access_token: "bot_token" }.to_json)
    end

    it "exchanges code for token" do
      controller.send(:bot_callback_handler, guild.id)
      
      expect(WebMock).to have_requested(:post, "https://discord.com/api/oauth2/token")
        .with(body: hash_including(grant_type: "authorization_code", code: code))
    end

    it "updates guild Discord setting connected_at" do
      create(:guild_discord_setting, guild: guild, discord_guild_id: guild_id)
      
      controller.send(:bot_callback_handler, guild.id)
      
      guild.reload
      expect(guild.guild_discord_setting.connected_at).to be_within(1.second).of(Time.current)
    end

    it "renders auto-close HTML" do
      controller.send(:bot_callback_handler, guild.id)
      rendered = controller.response.body

      expect(rendered).to include("window.opener.postMessage")
      expect(rendered).to include("window.close()")
    end
  end
end

