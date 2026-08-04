# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Activity feed", type: :request do
  let(:owner) { create(:user, auth_method: :discord) }
  let(:guild) { create(:guild, owner: owner) }
  let(:officer) { create(:user, auth_method: :discord) }
  let!(:officer_membership) { create(:guild_member, guild: guild, user: officer, status: :active, discord_role_id: "role-1") }

  let(:basic_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "basic").first ||
      create(:pricing_plan,
        name: "Basic",
        price: 9,
        price_display: "$9",
        period: "per month",
        max_guilds: 5,
        max_members_per_guild: 100,
        active: true,
        display_order: 91)
  end

  before do
    officer.subscribe_to_plan!(basic_plan)
    guild.update!(
      permission_role_1_id: "role-1",
      role_1_can_view_activity_feed: true
    )
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    sign_in officer
  end

  describe "sidebar member guild menu" do
    it "includes activity feed link when member has can_view_activity_feed" do
      get guild_path(guild)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(guild_activity_feed_path(guild))
    end

    it "omits activity feed link when slot flag is off" do
      guild.update!(role_1_can_view_activity_feed: false)
      get guild_path(guild)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(guild_activity_feed_path(guild))
    end
  end

  describe "GET /guilds/:id/activity_feed support_center_url in member chrome" do
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

    it "includes default support URL in HTML" do
      get guild_activity_feed_path(guild)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get guild_activity_feed_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://activity-feed-support.example/help")
      get guild_activity_feed_path(guild)
      expect(response.body).to include("https://activity-feed-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://activity-feed-support.example/help")
      get guild_activity_feed_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://activity-feed-support.example/help")
    end
  end

  describe "guild scoping" do
    let(:stranger) { create(:user, auth_method: :discord) }

    before do
      stranger.subscribe_to_plan!(basic_plan)
      sign_in stranger
    end

    it "redirects users with no access to the guild from activity feed export" do
      get guild_activity_feed_export_path(guild)
      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "GET /guilds/:id/activity_feed/export" do
    it "blocks export without activity feed permission" do
      guild.update!(role_1_can_view_activity_feed: false)
      get guild_activity_feed_export_path(guild)
      expect(response).to redirect_to(guild_path(guild))
    end

    it "returns CSV with current filters and UTC timestamps" do
      GuildActivityLog.create!(
        guild: guild,
        user: officer,
        action_type: "test_action",
        description: "Did something",
        metadata: { "name" => "X" }
      )
      other = create(:user)
      create(:guild_member, guild: guild, user: other, status: :active)
      GuildActivityLog.create!(
        guild: guild,
        user: other,
        action_type: "other_action",
        description: "Other"
      )

      get guild_activity_feed_export_path(guild, action_type: "test_action")

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/csv")
      body = response.body
      expect(body).to include("time_utc")
      expect(body).to include("Test action")
      expect(body.lines(chomp: true).size).to eq(2)
    end
  end
end
