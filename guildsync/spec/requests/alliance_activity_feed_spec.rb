# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Alliance activity feed", type: :request do
  let(:active_paid_plan) do
    plan = PricingPlan.find_or_create_by!(name: "RSpec Alliance Activity Feed Paid") do |p|
      p.price = 19
      p.price_display = "$19"
      p.period = "per month"
      p.max_guilds = 10
      p.max_members_per_guild = 100
      p.active = true
      p.display_order = 51
      p.can_create_alliance = true
    end
    plan.update!(can_create_alliance: true) unless plan.can_create_alliance?
    plan
  end

  let(:owner) do
    u = create(:user, :discord_auth, skip_free_plan_subscription: true)
    create(:subscription, user: u, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
    u
  end
  let(:guild) { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active, joined_at: Time.current)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end

  let(:member_only) do
    u = create(:user, :discord_auth, skip_free_plan_subscription: true)
    create(:subscription, user: u, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
    u
  end

  before { alliance }

  describe "GET /alliances/:alliance_id/activity_feed" do
    it "allows guild owner in alliance" do
      sign_in owner
      get alliance_activity_feed_path(alliance_id: alliance.id)
      expect(response).to have_http_status(:ok)
    end

    it "denies non-owner alliance member" do
      # Guild membership syncs AllianceMember via AllianceMemberSyncService
      create(:guild_member, guild: guild, user: member_only, status: :active)
      sign_in member_only
      get alliance_activity_feed_path(alliance_id: alliance.id)
      expect(response).to redirect_to(alliance_path(alliance))
      expect(flash[:alert]).to eq(I18n.t("alliance_activity_feed.access_denied"))
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      before { sign_in owner }

      it "includes default support URL in HTML" do
        get alliance_activity_feed_path(alliance_id: alliance.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get alliance_activity_feed_path(alliance_id: alliance.id), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-activity-feed-support.example/help")
        get alliance_activity_feed_path(alliance_id: alliance.id)
        expect(response.body).to include("https://alliance-activity-feed-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-activity-feed-support.example/help")
        get alliance_activity_feed_path(alliance_id: alliance.id), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-activity-feed-support.example/help")
      end
    end
  end

  describe "GET /alliances/:alliance_id/activity_feed/export" do
    it "returns CSV for owner with UTC timestamps and matching filters" do
      AllianceActivityLog.create!(
        alliance: alliance,
        guild: guild,
        user: owner,
        action_type: "test_action",
        description: "Did something",
        metadata: { "discord_server_name" => "Test Guild" }
      )
      other = create(:user, :discord_auth)
      AllianceActivityLog.create!(
        alliance: alliance,
        guild: guild,
        user: other,
        action_type: "other_action",
        description: "Other row"
      )

      sign_in owner
      get alliance_activity_feed_export_path(alliance_id: alliance.id, action_type: "test_action")

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/csv")
      body = response.body
      expect(body).to include("time_utc")
      expect(body).to include("test_action")
      expect(body).to include("Did something")
      expect(body.lines(chomp: true).size).to eq(2)
    end

    it "redirects non-owner alliance member" do
      create(:guild_member, guild: guild, user: member_only, status: :active)
      sign_in member_only
      get alliance_activity_feed_export_path(alliance_id: alliance.id)
      expect(response).to redirect_to(alliance_path(alliance))
    end
  end

  describe "GET /alliances/:alliance_id/activity_feed/export.json" do
    it "returns JSON rows for alliance owner" do
      AllianceActivityLog.create!(
        alliance: alliance,
        guild: guild,
        user: owner,
        action_type: "invite_accept",
        description: "Accepted",
        metadata: {}
      )
      sign_in owner
      get alliance_activity_feed_export_json_path(alliance_id: alliance.id)
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["alliance_id"]).to eq(alliance.id)
      expect(json["rows"].size).to eq(1)
      expect(json["rows"].first["action"]).to eq("invite_accept")
      expect(json["rows"].first["created_at_utc"]).to be_present
    end
  end
end
