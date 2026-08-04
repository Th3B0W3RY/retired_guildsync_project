# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end
  let(:guild) { create(:guild, owner: user) }

  before do
    guild.guild_members.find_or_create_by!(user: user) { |m| m.status = :active; m.role = :owner }
    sign_in user
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  describe "GET /dashboard" do
    it "returns success" do
      get dashboard_path
      expect(response).to have_http_status(:success)
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get dashboard_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get dashboard_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://member-dashboard-support.example/help")
        get dashboard_path
        expect(response.body).to include("https://member-dashboard-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://member-dashboard-support.example/help")
        get dashboard_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://member-dashboard-support.example/help")
      end
    end

    it "shows Recent Activity section" do
      get dashboard_path
      expect(response.body).to include("Recent Activity")
    end

    it "links to the full activity history page" do
      get dashboard_path
      expect(response.body).to include(dashboard_activity_path)
      expect(response.body).to include(I18n.t("user_activity.view_activity"))
    end

    it "shows Invite Members in Quick Actions when user has one invitable guild" do
      get dashboard_path
      expect(response.body).to include(I18n.t("dashboard.my_applications"))
      expect(response.body).to include(guild_applications_path)
    end

    it "shows Create Guild in Quick Actions when user can create a guild" do
      get dashboard_path
      expect(response.body).to include(I18n.t("dashboard.create_guild"))
    end

    context "when user cannot create another guild" do
      let(:pricing_plan) { create(:pricing_plan, max_guilds: 1, max_members_per_guild: 50, price: 1) }

      before do
        user.subscriptions.destroy_all
        create(:subscription, user: user, pricing_plan: pricing_plan)
        guild
        user.reload
      end

      it "hides Create Guild in Quick Actions" do
        get dashboard_path
        expect(response.body).not_to include("dashboard_quick_action_create_guild")
      end
    end

    it "shows member activity widgets" do
      get dashboard_path
      expect(response.body).to include("My Pending Items")
      expect(response.body).to include(I18n.t("dashboard.member_events_title"))
      expect(response.body).to include(I18n.t("dashboard.open_polls_title"))
      expect(response.body).to include(I18n.t("dashboard.open_loot_title"))
    end

    it "does not show guild-dependent quick actions in universal section" do
      get dashboard_path
      expect(response.body).not_to include("Create Event")
      expect(response.body).not_to include("Start Poll")
      expect(response.body).not_to include("Start Loot Roll")
      expect(response.body).not_to include("Invite Members")
    end

    it "shows global quick actions consistent with access" do
      guild
      get dashboard_path
      expect(response.body).to include(I18n.t("dashboard.view_guilds", default: "View Guilds"))
      expect(response.body).to include("My Applications")
      expect(response.body).to include("Apply to Guild")
      expect(response.body).to include(I18n.t("dashboard.archived_guilds", default: "Archived Guilds"))
      expect(response.body).not_to include(I18n.t("dashboard.alliances", default: "Alliances"))
    end

    it "shows Alliances quick action when user is tied to an active alliance" do
      g = guild
      a = create(:alliance, leader_guild: g, leader_user: user)
      create(:alliance_guild, alliance: a, guild: g, status: :active, joined_at: Time.current)
      get dashboard_path
      expect(response.body).to include(I18n.t("dashboard.alliances"))
    end

    it "shows Universal Menu collapsible wrapping global sidebar links" do
      get dashboard_path
      expect(response.body).to include(I18n.t("sidebar.universal_menu"))
      expect(response.body).to include('data-guild-id="universal-menu"')
    end

    context "sidebar Discord account status in universal menu" do
      it "shows disconnected state with red dot and outline when user has no Discord OAuth" do
        get dashboard_path
        expect(response.body).to include(I18n.t("sidebar.discord_not_connected_heading"))
        expect(response.body).to include("border-red-500/50")
        expect(response.body).to include("bg-red-500")
      end

      it "shows Connected as line with Discord username and green styling when OAuth is linked" do
        create(:user_discord_connection, user: user, discord_username: "cooluser#1234")
        get dashboard_path
        expect(response.body).to include(I18n.t("sidebar.connected_as", username: "cooluser"))
        expect(response.body).to include("border-green-500/30")
        expect(response.body).to include("bg-green-500")
      end
    end

    it "shows My warnings under universal sidebar when user can access a guild" do
      get dashboard_path
      label = I18n.t("sidebar.guild_menu.my_warnings")
      expect(response.body).to include(label)
      expect(response.body).to include(guild_my_warnings_path(guild))
      expect(response.body.scan(label).length).to eq(1)
    end

    context "when user owns multiple guilds" do
      let(:pricing_plan) { create(:pricing_plan, max_guilds: 10, max_members_per_guild: 100, price: 1) }
      let(:guild) { create(:guild, owner: user, name: "Aaron Guild") }
      let(:guild_other) { create(:guild, owner: user, name: "Zed Guild") }

      before do
        user.subscriptions.destroy_all
        create(:subscription, user: user, pricing_plan: pricing_plan)
        user.reload
        guild_other.guild_members.find_or_create_by!(user: user) { |m| m.status = :active; m.role = :owner }
      end

      it "uses the current guild for the universal My warnings link on guild pages" do
        get guild_path(guild_other)
        expect(response.body).to include(guild_my_warnings_path(guild_other))
        expect(response.body).not_to include(guild_my_warnings_path(guild))
      end
    end
  end

  describe "GET /dashboard/recent_activity" do
    it "returns success and HTML partial when authenticated" do
      get dashboard_recent_activity_path
      expect(response).to have_http_status(:success)
      expect(response.media_type).to include("text/html")
    end

    it "includes activity list or empty message" do
      get dashboard_recent_activity_path
      body = response.body
      expect(body.include?("recent") || body.include?("activity") || body.include?("No recent")).to be true
    end

    context "when user has recent activities" do
      before do
        create(:user_recent_activity, user: user, path: "/guilds/#{guild.id}", label: "Viewed #{guild.name}", link_path: "/guilds/#{guild.id}")
      end

      it "returns markup containing the activity label" do
        get dashboard_recent_activity_path
        expect(response.body).to include(guild.name)
      end

      it "renders linkable activities as anchors" do
        get dashboard_recent_activity_path
        expect(response.body).to include("href=\"/guilds/#{guild.id}\"")
      end
    end

    context "when an activity has no link_path (e.g. a sign-in)" do
      before do
        create(:user_recent_activity, user: user, path: "/auth/discord/callback", label: "Signed in with Discord", link_path: nil)
      end

      it "renders the label as plain text, not a link" do
        get dashboard_recent_activity_path
        expect(response.body).to include("Signed in with Discord")
        expect(response.body).not_to include("href=\"/auth/discord/callback\"")
      end
    end
  end

  describe "GET /dashboard/stats" do
    it "returns success and HTML partial when authenticated" do
      get dashboard_stats_path

      expect(response).to have_http_status(:success)
      expect(response.media_type).to include("text/html")
      expect(response.body).to include("My Pending Items")
      expect(response.body).to include(I18n.t("dashboard.open_polls_title"))
    end

    context "member activity aggregates" do
      let(:other_owner) { create(:user) }
      let(:other_guild) { create(:guild, owner: other_owner) }

      def open_poll_and_loot_counts(html)
        html.scan(/text-5xl font-bold leading-\[56px\] text-indigo-400 tabular-nums">(\d+)</).flatten.map(&:to_i)
      end

      it "counts open loot rolls only while still within deadline" do
        create(:loot_roll, :expired, guild: guild, creator: user)
        get dashboard_stats_path
        _polls, loot = open_poll_and_loot_counts(response.body)
        expect(loot).to eq(0)
      end

      it "includes loot rolls that are open with a future deadline" do
        create(:loot_roll, guild: guild, creator: user, status: :open, deadline_at: 2.hours.from_now)
        get dashboard_stats_path
        _polls, loot = open_poll_and_loot_counts(response.body)
        expect(loot).to eq(1)
      end

      it "does not count polls in guilds where the user is not a member" do
        create(:poll, guild: other_guild, creator: other_owner)
        get dashboard_stats_path
        polls, _loot = open_poll_and_loot_counts(response.body)
        expect(polls).to eq(0)
      end

      it "does not count polls in archived guilds where the user is only an active member" do
        archived = create(:guild, :archived, owner: other_owner)
        archived.guild_members.find_or_create_by!(user: user) { |m| m.status = :active; m.role = :member }
        create(:poll, guild: archived, creator: other_owner, deadline: 1.week.from_now)
        get dashboard_stats_path
        polls, _loot = open_poll_and_loot_counts(response.body)
        expect(polls).to eq(0)
      end

      it "does not count polls in guilds where the user is an inactive member" do
        other_guild.guild_members.find_or_create_by!(user: user) { |m| m.status = :inactive; m.role = :member }
        create(:poll, guild: other_guild, creator: other_owner, deadline: 1.week.from_now)
        get dashboard_stats_path
        polls, _loot = open_poll_and_loot_counts(response.body)
        expect(polls).to eq(0)
      end
    end
  end

  describe "dashboard polling hooks" do
    it "renders stats poll controller in desktop dashboard" do
      get dashboard_path
      expect(response.body).to include("data-controller=\"dashboard-stats-poll\"")
      expect(response.body).to include(dashboard_stats_path)
    end
  end
end

RSpec.describe "Dashboard without guilds", type: :request do
  let(:user) do
    u = create(:user)
    u.update!(auth_method: "discord")
    u
  end

  before do
    sign_in user
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  it "does not show My warnings in the sidebar" do
    get dashboard_path
    expect(response.body).not_to include(I18n.t("sidebar.guild_menu.my_warnings"))
  end

  it "does not show Archived Guilds in quick actions or universal menu" do
    get dashboard_path
    label = I18n.t("dashboard.archived_guilds")
    expect(response.body).not_to include(label)
    expect(response.body).not_to include(I18n.t("sidebar.archived_guilds"))
  end

  it "still shows Universal Menu toggle for users without guilds" do
    get dashboard_path
    expect(response.body).to include(I18n.t("sidebar.universal_menu"))
  end
end
