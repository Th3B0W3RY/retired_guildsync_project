# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Guilds", type: :request do
  let(:user) do
    # Skip Free plan subscription creation so we can create a test subscription
    u = build(:user, skip_free_plan_subscription: true)
    # Set auth_method to "discord" to bypass MFA checks in tests
    u.auth_method = "discord"
    u.save!
    u
  end
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:subscription) { create(:subscription, user: user, pricing_plan: pricing_plan) }
  let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

  before do
    sign_in user
  end


  describe "GET /guilds" do
    describe "support_center_url in member chrome" do
      before { create(:guild, owner: user) }

      it "includes default support URL in HTML" do
        get "/guilds"
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get "/guilds", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://my-guilds-list-support.example/help")
        get "/guilds"
        expect(response.body).to include("https://my-guilds-list-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://my-guilds-list-support.example/help")
        get "/guilds", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://my-guilds-list-support.example/help")
      end
    end

    it "lists user's guilds" do
      # Factory automatically creates GuildMember for owner, so we don't need to create them manually
      guild1 = create(:guild, owner: user)
      guild2 = create(:guild, owner: user)
      
      get "/guilds"
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include(guild1.name)
      expect(response.body).to include(guild2.name)
    end

    context "when user is at max guilds for their plan" do
      before { pricing_plan.update!(max_guilds: 1) }

      it "does not show create-guild CTAs on the index" do
        create(:guild, owner: user)
        get "/guilds"
        expect(response.body).not_to include(I18n.t("guilds.index.create_new_guild"))
        expect(response.body).not_to include(I18n.t("guilds.index.create_first_guild"))
      end
    end
  end

  describe "GET /guilds/new" do
    it "shows guild creation form" do
      get "/guilds/new"
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Create Guild")
      expect(response.body).to include('id="guild_name_field"')
      expect(response.body).to include("data-recruiting-blocklist")
      expect(response.body).to include(I18n.t("guilds.new.recruiting_name_warning"))
    end

    describe "support_center_url in member chrome" do
      it "includes default support URL in HTML" do
        get new_guild_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get new_guild_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-new-form-support.example/help")
        get new_guild_path
        expect(response.body).to include("https://guild-new-form-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-new-form-support.example/help")
        get new_guild_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-new-form-support.example/help")
      end
    end
  end

  describe "POST /guilds" do
    let!(:test_game) do
      Game.find_or_create_by!(name: "Test Game", slug: "test-game") do |g|
        g.description = "Default test game"
        g.active = true
        g.ocr_config = {}
      end
    end

    it "creates a new guild" do
      expect {
        post "/guilds", params: {
          guild: {
            name: "My New Guild",
            description: "A test guild",
            game_ids: [test_game.id],
            primary_game_id: test_game.id
          }
        }
      }.to change { Guild.count }.by(1)
      
      expect(response).to redirect_to(guild_path(Guild.last))
      expect(Guild.last.owner).to eq(user)
      expect(Guild.last.members).to include(user)
    end

    it "enforces max_guilds limit" do
      pricing_plan.update!(max_guilds: 1)
      create(:guild, owner: user)
      
      expect {
        post "/guilds", params: {
          guild: {
            name: "Second Guild",
            description: "Should fail",
            game_ids: [test_game.id],
            primary_game_id: test_game.id
          }
        }
      }.not_to change { Guild.count }
      
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to include("Guild limit reached")
    end

    it "creates a guild with a dynamically added game" do
      # First, create a new game via the suggest endpoint (simulating user adding a new game)
      new_game_name = "Dynamically Added Game #{Time.current.to_i}"
      
      expect {
        post "/games/suggest", params: {
          name: new_game_name
        }, as: :json
      }.to change { Game.count }.by(1)
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response["success"]).to be true
      expect(json_response["game"]["name"]).to eq(new_game_name)
      
      new_game_id = json_response["game"]["id"].to_i
      new_game = Game.find(new_game_id)
      expect(new_game.active).to be false # New games are created as inactive (pending approval)
      
      # Now create a guild with the newly created game
      expect {
        post "/guilds", params: {
          guild: {
            name: "Guild With New Game",
            description: "A guild using a dynamically added game",
            game_ids: [new_game_id],
            primary_game_id: new_game_id
          }
        }
      }.to change { Guild.count }.by(1)
        .and change { GuildMember.count }.by(1)
        .and change { GuildGame.count }.by(1)
      
      expect(response).to redirect_to(guild_path(Guild.last))
      
      guild = Guild.last
      expect(guild.owner).to eq(user)
      expect(guild.members).to include(user)
      expect(guild.games).to include(new_game)
      expect(guild.primary_game).to eq(new_game)
      
      # Verify the guild_game association
      guild_game = guild.guild_games.find_by(game_id: new_game_id)
      expect(guild_game).to be_present
      expect(guild_game.primary).to be true
      
      # Verify the owner is added as a member
      owner_member = guild.guild_members.find_by(user_id: user.id)
      expect(owner_member).to be_present
      expect(owner_member.role).to eq("owner")
      expect(owner_member.status).to eq("active")
    end
  end

  describe "GET /guilds/:id/discord/connect" do
    let(:guild) { create(:guild, owner: user) }

    it "shows Discord connection page" do
      get guild_connect_discord_path(guild)
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Connect Bot To Guild Discord")
    end
  end

  describe "DELETE /guilds/:guild_id/discord_connection" do
    let(:guild) { create(:guild, owner: user) }
    let!(:discord_setting) { create(:guild_discord_setting, guild: guild) }

    it "disconnects Discord from guild" do
      delete "/guilds/#{guild.id}/discord_connection"
      
      expect(response).to redirect_to(guild_discord_connection_path(guild))
      expect(guild.reload.guild_discord_setting).to be_nil
    end
  end
end

