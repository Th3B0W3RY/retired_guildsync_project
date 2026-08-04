# frozen_string_literal: true

require "base64"
require "stringio"
require "rails_helper"

RSpec.describe "Guild settings scroll restore (POST + redirect)", type: :request do
  let(:owner) do
    u = build(:user, skip_free_plan_subscription: true)
    u.auth_method = "discord"
    u.save!
    u
  end
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:subscription) { create(:subscription, user: owner, pricing_plan: pricing_plan) }
  let!(:guild) { create(:guild, owner: owner) }

  before do
    sign_in owner
    set_mfa_verified_in_session
  end

  shared_examples "settings page includes scroll restore hook" do
    it "scopes Stimulus submit-scroll-restore with a per-guild storage key" do
      expect(response.body).to include('data-controller="submit-scroll-restore"')
      expect(response.body).to include(%(data-submit-scroll-restore-key-value="gs:guild-settings:#{guild.id}"))
    end

    it "marks the games list scroll container for nested scroll restoration" do
      expect(response.body).to include('data-submit-scroll-restore-target="scrollContainer"')
    end

    it "exposes the games section id so update_games anchor redirect lands here" do
      expect(response.body).to include('id="guild-games-section"')
    end

    it "wraps the games card in a Turbo Frame so submits update in place" do
      expect(response.body).to match(/<turbo-frame[^>]*\sid="guild_games_section"/)
    end
  end

  context "when the guild already has a logo (logo auto-upload script present)" do
    before do
      png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
      guild.logo.attach(io: StringIO.new(png), filename: "1x1.png", content_type: "image/png")
    end

    it "uses requestSubmit for programmatic logo form submit so capture-phase listeners run" do
      get guild_settings_path(guild), headers: { "User-Agent" => MobileVariantRequestHelpers::DESKTOP_CHROME_UA }
      expect(response.body).to include("requestSubmit")
    end
  end

  describe "GET /guilds/:id/settings (desktop)" do
    before { get guild_settings_path(guild), headers: { "User-Agent" => MobileVariantRequestHelpers::DESKTOP_CHROME_UA } }

    include_examples "settings page includes scroll restore hook"
  end

  describe "GET /guilds/:id/settings (mobile variant)" do
    before { get guild_settings_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA) }

    include_examples "settings page includes scroll restore hook"
  end

  describe "PATCH /guilds/:id/games (update_games) — HTML anchor redirect (no-Turbo fallback)" do
    let!(:game)       { create(:game) }
    let!(:other_game) { create(:game) }

    it "redirects to the games section anchor when no games selected" do
      patch guild_update_games_path(guild), params: { game_ids: [], primary_game_id: nil }
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to end_with("#guild-games-section")
    end

    it "redirects to the games section anchor when primary game is missing" do
      patch guild_update_games_path(guild), params: { game_ids: [ game.id, other_game.id ], primary_game_id: nil }
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to end_with("#guild-games-section")
    end

    it "redirects to the games section anchor on successful update" do
      patch guild_update_games_path(guild), params: { game_ids: [ game.id, other_game.id ], primary_game_id: game.id.to_s }
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to end_with("#guild-games-section")
    end
  end

  describe "PATCH /guilds/:id/games (update_games) — Turbo Stream in-place update" do
    let!(:game)       { create(:game) }
    let!(:other_game) { create(:game) }
    let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

    shared_examples "in-place turbo stream response" do
      it "responds with text/vnd.turbo-stream.html (no full reload)" do
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "replaces the guild_games_section frame" do
        expect(response.body).to include('action="replace"')
        expect(response.body).to include('target="guild_games_section"')
      end

      it "dispatches a toast:show event targeting the toast host" do
        expect(response.body).to include('target="toast-host"')
        expect(response.body).to include('toast:show')
      end
    end

    context "when no games are selected" do
      before do
        patch guild_update_games_path(guild),
              params: { game_ids: [], primary_game_id: nil },
              headers: turbo_headers
      end
      include_examples "in-place turbo stream response"
    end

    context "when primary game is missing" do
      before do
        patch guild_update_games_path(guild),
              params: { game_ids: [ game.id, other_game.id ], primary_game_id: nil },
              headers: turbo_headers
      end
      include_examples "in-place turbo stream response"
    end

    context "on a successful update" do
      before do
        patch guild_update_games_path(guild),
              params: { game_ids: [ game.id, other_game.id ], primary_game_id: game.id.to_s },
              headers: turbo_headers
      end
      include_examples "in-place turbo stream response"

      it "persists the new selection" do
        expect(guild.reload.games.pluck(:id)).to match_array([ game.id, other_game.id ])
        expect(guild.primary_game).to eq(game)
      end
    end
  end

  describe "Role Sync card layout stabilization (when Discord connected and bot present)" do
    let!(:discord_setting) do
      GuildDiscordSetting.create!(
        guild: guild,
        discord_guild_id: "1111111111",
        discord_guild_name: "Test Server",
        connected_at: Time.current
      )
    end

    before do
      allow_any_instance_of(DiscordService).to receive(:get_guild).and_return({ "id" => discord_setting.discord_guild_id })
      allow_any_instance_of(DiscordService).to receive(:get_guild_channels).and_return([])
      get guild_settings_path(guild), headers: { "User-Agent" => MobileVariantRequestHelpers::DESKTOP_CHROME_UA }
    end

    it "reserves vertical space on the Role Sync card so async XHR rows do not reflow the Games card" do
      expect(response.body).to include('min-h-[28rem]')
      expect(response.body).to include('data-controller="discord-role-sync"')
    end
  end
end
