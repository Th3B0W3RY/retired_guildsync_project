# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guild Visibility", type: :request do
  let(:owner) do
    u = build(:user, skip_free_plan_subscription: true)
    u.auth_method = "discord"
    u.save!
    u
  end
  let(:other_user) do
    u = build(:user, skip_free_plan_subscription: true)
    u.auth_method = "discord"
    u.save!
    u
  end
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:subscription_owner) { create(:subscription, user: owner, pricing_plan: pricing_plan) }
  let!(:subscription_other) { create(:subscription, user: other_user, pricing_plan: pricing_plan) }

  let!(:public_guild)  { create(:guild, owner: owner, publicly_listed: true) }
  let!(:private_guild) { create(:guild, owner: owner, publicly_listed: false) }
  let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

  # ────────────────────────────────────────────────────────────
  # Member Dashboard — Available Guilds
  # ────────────────────────────────────────────────────────────

  describe "GET /member/dashboard (Available Guilds)" do
    before { sign_in other_user }

    it "includes publicly listed guilds" do
      get "/member/dashboard"
      expect(assigns(:available_guilds)).to include(public_guild)
    end

    it "excludes privately listed guilds" do
      get "/member/dashboard"
      expect(assigns(:available_guilds)).not_to include(private_guild)
    end

    it "excludes archived publicly listed guilds" do
      archived_listed = create(:guild, owner: owner, publicly_listed: true,
        archived_at: Time.current, scheduled_purge_at: 1.year.from_now)
      get "/member/dashboard"
      expect(assigns(:available_guilds)).not_to include(archived_listed)
    end
  end

  describe "GET /member/dashboard support_center_url in member chrome" do
    before { sign_in other_user }

    it "includes default support URL in HTML" do
      get "/member/dashboard"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get "/member/dashboard", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://member-dashboard-support.example/help")
      get "/member/dashboard"
      expect(response.body).to include("https://member-dashboard-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://member-dashboard-support.example/help")
      get "/member/dashboard", headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://member-dashboard-support.example/help")
    end
  end

  # ────────────────────────────────────────────────────────────
  # Guild Search
  # ────────────────────────────────────────────────────────────

  describe "GET /guilds/search" do
    before { sign_in other_user }

    it "returns publicly listed guilds matching the query" do
      get "/guilds/search", params: { q: public_guild.name }
      json = response.parsed_body
      rows = json["results"] || []
      ids = rows.map { |g| g["id"] }
      expect(ids).to include(public_guild.id)
    end

    it "does not return privately listed guilds matching the query" do
      get "/guilds/search", params: { q: private_guild.name }
      json = response.parsed_body
      rows = json["results"] || []
      ids = rows.map { |g| g["id"] }
      expect(ids).not_to include(private_guild.id)
    end

    it "does not return archived publicly listed guilds matching the query" do
      archived = create(:guild, owner: owner, publicly_listed: true,
        archived_at: Time.current, scheduled_purge_at: 1.year.from_now)
      get "/guilds/search", params: { q: archived.name }
      json = response.parsed_body
      ids = (json["results"] || []).map { |g| g["id"] }
      expect(ids).not_to include(archived.id)
    end

    it "paginates search results using page and per_page" do
      11.times do |i|
        create(:guild, publicly_listed: true, name: "VisPag Guild #{i}")
      end

      get "/guilds/search", params: { q: "VisPag Guild", page: 1, per_page: 10 }
      json = response.parsed_body
      expect(json["results"].size).to eq(10)
      expect(json["pagination"]).to include(
        "page" => 1,
        "per_page" => 10,
        "total_count" => 11,
        "total_pages" => 2
      )

      get "/guilds/search", params: { q: "VisPag Guild", page: 2, per_page: 10 }
      expect(response.parsed_body["results"].size).to eq(1)
      expect(response.parsed_body["pagination"]["page"]).to eq(2)
    end
  end

  # ────────────────────────────────────────────────────────────
  # Guild Settings — toggle publicly_listed
  # ────────────────────────────────────────────────────────────

  describe "PATCH /guilds/:id (visibility toggle)" do
    before { sign_in owner }

    it "sets guild to private when publicly_listed is unchecked (0)" do
      patch "/guilds/#{public_guild.id}", params: {
        guild: { publicly_listed: "0" }
      }
      expect(public_guild.reload.publicly_listed).to be false
    end

    it "sets guild to public when publicly_listed is checked (1)" do
      patch "/guilds/#{private_guild.id}", params: {
        guild: { publicly_listed: "1" }
      }
      expect(private_guild.reload.publicly_listed).to be true
    end

    context "when a plain member (no settings permission) tries to toggle visibility" do
      # other_user is a real active member of the guild but has no discord_role_id
      # and no permission_role_* is configured, so can_manage_guild_settings? returns false.
      # This correctly exercises the authorization guard (not just set_guild membership access).
      before do
        create(:guild_member, guild: public_guild, user: other_user, role: :member, status: :active)
        sign_out owner
        sign_in other_user
      end

      it "is denied and does not change publicly_listed" do
        patch "/guilds/#{public_guild.id}", params: {
          guild: { publicly_listed: "0" }
        }
        expect(response).to redirect_to(guild_path(public_guild))
        expect(public_guild.reload.publicly_listed).to be true
      end
    end

    context "when a member WITH settings permission tries to toggle visibility" do
      before do
        # Give the guild a permission role for settings
        public_guild.update!(
          permission_role_1_id: "ADMIN_ROLE_ID",
          role_1_can_manage_guild_settings: true
        )
        # Give the user that role
        create(:guild_member, guild: public_guild, user: other_user, role: :member, status: :active, discord_role_id: "ADMIN_ROLE_ID")
        sign_out owner
        sign_in other_user
      end

      it "is allowed and changes publicly_listed" do
        patch "/guilds/#{public_guild.id}", params: {
          guild: { publicly_listed: "0" }
        }
        expect(public_guild.reload.publicly_listed).to be false
      end
    end

    context "when a completely unrelated non-member user tries to toggle visibility" do
      before do
        sign_out owner
        sign_in other_user
      end

      it "is denied by set_guild (no membership) and does not change publicly_listed" do
        patch "/guilds/#{public_guild.id}", params: {
          guild: { publicly_listed: "0" }
        }
        expect(response).to redirect_to(my_guilds_path)
        expect(public_guild.reload.publicly_listed).to be true
      end
    end
  end

  # ────────────────────────────────────────────────────────────
  # Guild Settings page renders visibility section
  # ────────────────────────────────────────────────────────────

  describe "GET /guilds/:id/settings" do
    before { sign_in owner }

    describe "support_center_url in member chrome" do
      before do
        allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
      end

      it "includes default support URL in HTML" do
        get guild_settings_path(public_guild)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get guild_settings_path(public_guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-settings-support.example/help")
        get guild_settings_path(public_guild)
        expect(response.body).to include("https://guild-settings-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-settings-support.example/help")
        get guild_settings_path(public_guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-settings-support.example/help")
      end
    end

    context "when Discord is connected (role permissions matrix visible)" do
      before do
        ds = create(:guild_discord_setting, guild: public_guild)
        allow_any_instance_of(DiscordService).to receive(:get_guild).and_return({ "id" => ds.discord_guild_id })
        allow_any_instance_of(DiscordService).to receive(:get_guild_channels).and_return([])
      end

      it "includes edit-scanned-gear-stats checkboxes for all four role slots (desktop)" do
        get guild_settings_path(public_guild), headers: { "User-Agent" => MobileVariantRequestHelpers::DESKTOP_CHROME_UA }
        expect(response).to have_http_status(:success)
        (1..4).each do |n|
          expect(response.body).to include(%(name="guild[role_#{n}_can_edit_gear_scanned_stats]"))
        end
      end

      it "includes the same checkboxes on the mobile settings variant" do
        get guild_settings_path(public_guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include('name="guild[role_1_can_edit_gear_scanned_stats]"')
        expect(response.body).to include('name="guild[role_4_can_edit_gear_scanned_stats]"')
      end
    end

    it "renders the visibility section" do
      get "/guilds/#{public_guild.id}/settings"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Guild Visibility")
    end

    it "shows the visibility checkbox as checked for a public guild" do
      get "/guilds/#{public_guild.id}/settings"
      # Match `checked` tied to our specific checkbox ID in either attribute order,
      # guarded by tag boundaries so it cannot match a different element.
      expect(response.body).to match(
        /checked[^>]*id="guild_publicly_listed"|id="guild_publicly_listed"[^>]*checked/
      )
    end

    it "shows the visibility checkbox as unchecked for a private guild" do
      get "/guilds/#{private_guild.id}/settings"
      # The element must exist on the page ...
      expect(response.body).to include('id="guild_publicly_listed"')
      # ... but must NOT carry the checked attribute.
      expect(response.body).not_to match(
        /checked[^>]*id="guild_publicly_listed"|id="guild_publicly_listed"[^>]*checked/
      )
    end
  end
end
