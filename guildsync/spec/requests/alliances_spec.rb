# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Alliances", type: :request do
  # App enforces MFA for auth_method :mfa; Discord OAuth users skip that path (see ApplicationController).
  # Alliance routes require a non-free plan with active access (paid subscription or in-date paid-tier trial).
  let(:active_paid_plan) do
    plan = PricingPlan.find_or_create_by!(name: "RSpec Alliance Paid Base") do |p|
      p.price = 19
      p.price_display = "$19"
      p.period = "per month"
      p.max_guilds = 10
      p.max_members_per_guild = 100
      p.active = true
      p.display_order = 50
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
  let(:guild)    { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active, joined_at: Time.current)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end
  let(:other_user) do
    u = create(:user, :discord_auth, skip_free_plan_subscription: true)
    create(:subscription, user: u, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
    u
  end

  before { sign_in owner }

  describe "GET /alliances/:id (show)" do
    it "renders the alliance page for a member" do
      get alliance_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "redirects non-members with access_denied (same as unknown id)" do
      sign_in other_user
      get alliance_path(alliance)
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "redirects for an unknown alliance id" do
      get alliance_path(0)
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "redirects a free-plan user who is not an alliance member before member check (plan gate)" do
      free_user = create(:user, :discord_auth)
      sign_in free_user
      get alliance_path(alliance)
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("alliances.errors.plan_required_for_alliance_hub"))
    end
  end

  describe "GET /alliances/:id (show) support_center_url in member chrome" do
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

    before { alliance }

    it "includes default support URL in HTML" do
      get alliance_path(alliance)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get alliance_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://alliance-show-support.example/help")
      get alliance_path(alliance)
      expect(response.body).to include("https://alliance-show-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://alliance-show-support.example/help")
      get alliance_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://alliance-show-support.example/help")
    end
  end

  describe "GET /alliances (index)" do
    before { alliance } # materialize alliance + membership for hub

    it "shows open alliance card when user is an alliance member" do
      get alliances_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(alliance.name)
      expect(response.body).to include("Open Alliance")
    end

    it "renders blank hub when user has no alliance membership" do
      sign_in other_user
      get alliances_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Join a guild with an alliance")
      expect(response.body).not_to include("Request to join an alliance")
      expect(response.body).not_to include("Create an Alliance")
    end

    it "redirects a free-plan user away from the alliance hub when not an alliance member" do
      free_user = create(:user, :discord_auth)
      sign_in free_user
      get alliances_path
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("alliances.errors.plan_required_for_alliance_hub"))
    end

    it "allows a free-plan user who is an active alliance member to open the hub" do
      free_member = create(:user, :discord_auth)
      create(:guild_member, guild: guild, user: free_member, role: :member, status: :active)
      sign_in free_member
      get alliances_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(alliance.name)
    end
  end

  describe "GET /alliances (index) support_center_url in member chrome" do
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

    before { alliance }

    it "includes default support URL in HTML" do
      get alliances_path
      expect(response.body).to include(default_support_url)
    end

    it "includes default support URL on mobile variant" do
      get alliances_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include(default_support_url)
    end

    it "includes configured custom support URL when set" do
      SiteSetting.set("release_notes_url", "https://alliances-hub-support.example/help")
      get alliances_path
      expect(response.body).to include("https://alliances-hub-support.example/help")
    end

    it "includes configured custom support URL on mobile variant when set" do
      SiteSetting.set("release_notes_url", "https://alliances-hub-support.example/help")
      get alliances_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
      expect(response.body).to include("https://alliances-hub-support.example/help")
    end
  end

  describe "GET /alliances/new" do
    # #new requires a guild the user can manage that is not already in an alliance
    let(:solo_owner) { create(:user, :discord_auth) }
    let(:solo_guild) { create(:guild, owner: solo_owner) }

    before do
      solo_guild
      sign_in solo_owner
    end

    context "when user has a free plan" do
      it "redirects with the hub plan message when not an alliance member" do
        get new_alliance_path
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:alert]).to eq(I18n.t("alliances.errors.plan_required_for_alliance_hub"))
      end
    end

    context "when user has a paid plan that does not include alliances" do
      let(:solo_no_alliance_plan) do
        plan = PricingPlan.find_or_initialize_by(name: "RSpec Paid No Alliance")
        plan.assign_attributes(
          price: 8,
          price_display: "$8",
          period: "per month",
          max_guilds: 5,
          max_members_per_guild: 50,
          active: true,
          display_order: 51,
          can_create_alliance: false
        )
        plan.save!
        plan
      end

      let(:solo_owner) { create(:user, :discord_auth, skip_free_plan_subscription: true) }

      before do
        create(:subscription, user: solo_owner, pricing_plan: solo_no_alliance_plan, status: :active, started_at: Time.current)
        solo_guild
        sign_in solo_owner
      end

      it "redirects to upgrade pricing" do
        get new_alliance_path
        expect(response).to redirect_to(upgrade_pricing_path)
      end
    end
  end

  describe "GET /alliances/new (trialing paid plan)" do
    let(:trialing_user) { create(:user, :discord_auth, skip_free_plan_subscription: true) }
    let(:paid_plan) do
      plan = PricingPlan.find_or_create_by!(name: "Upgraded") do |p|
        p.price = 16
        p.price_display = "$16"
        p.period = "per month"
        p.max_guilds = 15
        p.max_members_per_guild = 200
        p.max_polls = 100
        p.max_loot_rolls = 80
        p.max_events = 100
        p.active = true
        p.display_order = 2
        p.can_create_alliance = true
      end
      plan.update!(can_create_alliance: true) unless plan.can_create_alliance?
      plan
    end

    before do
      create(:subscription,
             user: trialing_user,
             pricing_plan: paid_plan,
             status: :trialing,
             started_at: Time.current,
             trial_ends_at: User::STANDARD_TRIAL_PERIOD_DAYS.days.from_now)
      create(:guild, owner: trialing_user)
      sign_in trialing_user
    end

    it "renders the new alliance form" do
      get new_alliance_path
      expect(response).to have_http_status(:ok)
    end

    it "uses multipart/form-data so alliance logo files are submitted to Active Storage" do
      get new_alliance_path
      expect(response.body).to include('enctype="multipart/form-data"')
    end
  end

  describe "POST /alliances" do
    let(:poster) { create(:user, :discord_auth, skip_free_plan_subscription: true) }
    let(:poster_guild) { create(:guild, owner: poster) }

    before do
      # Subscription before guild so the guild factory does not attach a free/nil-price "Test Plan" first.
      create(:subscription, user: poster, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      poster_guild
      sign_in poster
    end

    it "creates an alliance and redirects" do
      expect {
        post alliances_path, params: { alliance: { name: "Iron Pact", description: "Test" } }
      }.to change(Alliance, :count).by(1)
      expect(response).to redirect_to(alliance_path(Alliance.last))
    end

    it "re-renders new on invalid params" do
      post alliances_path, params: { alliance: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not allow an officer with can_manage_alliance to create an alliance (owner only)" do
      officer = create(:user, :discord_auth)
      create(:guild_member, guild: poster_guild, user: officer, status: :active).update!(discord_role_id: "role-1")
      poster_guild.update!(permission_role_1_id: "role-1", role_1_can_manage_alliance: true)
      sign_in officer

      expect {
        post alliances_path, params: { alliance: { name: "Officer Pact", description: "Test" } }
      }.not_to change(Alliance, :count)
      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "GET /alliances/:id/edit" do
    it "uses multipart/form-data for alliance logo uploads" do
      get edit_alliance_path(alliance)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('enctype="multipart/form-data"')
    end
  end

  describe "PATCH /alliances/:id" do
    it "allows the leader to update the alliance" do
      patch alliance_path(alliance), params: { alliance: { name: "New Name", description: "Updated" } }
      expect(response).to redirect_to(alliance_path(alliance))
      expect(alliance.reload.name).to eq("New Name")
    end

    it "rejects updates from non-leaders" do
      sign_in other_user
      create(:alliance_member, alliance: alliance, user: other_user, guild: guild, role: :member, status: :active)
      patch alliance_path(alliance), params: { alliance: { name: "Hijack" } }
      expect(response).to redirect_to(alliance_path(alliance))
      expect(alliance.reload.name).not_to eq("Hijack")
    end
  end

  describe "DELETE /alliances/:id (disband)" do
    it "allows the Alliance Leader to disband" do
      delete alliance_path(alliance)
      expect(response).to redirect_to(dashboard_path)
      expect(alliance.reload).to be_disbanded
    end

    it "does not allow a non-leader to disband" do
      sign_in other_user
      create(:alliance_member, alliance: alliance, user: other_user, guild: guild, role: :member, status: :active)
      delete alliance_path(alliance)
      expect(response).to redirect_to(alliance_path(alliance))
      expect(alliance.reload).to be_active
    end

    it "does not allow a regular member to disband even if majority votes exist" do
      g2_owner = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: g2_owner, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      guild2 = create(:guild, owner: g2_owner)
      create(:alliance_guild, alliance: alliance, guild: guild2, status: :active, joined_at: Time.current)
      create(:alliance_member, alliance: alliance, user: g2_owner, guild: guild2, role: :gm, status: :active)
      create(:alliance_disband_vote, alliance: alliance, user: owner, guild: guild, vote: true)
      create(:alliance_disband_vote, alliance: alliance, user: g2_owner, guild: guild2, vote: true)

      member = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: member, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      create(:alliance_member, alliance: alliance, user: member, guild: guild, role: :member, status: :active)
      sign_in member

      delete alliance_path(alliance)
      expect(response).to redirect_to(alliance_path(alliance))
      expect(alliance.reload).to be_active
    end
  end

  describe "POST /alliances/:id/leave" do
    let(:guild2_owner_user) do
      u = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      u
    end
    let(:guild2) { create(:guild, owner: guild2_owner_user) }

    before do
      create(:alliance_guild,  alliance: alliance, guild: guild2, status: :active, joined_at: Time.current)
      create(:alliance_member, alliance: alliance, user: guild2_owner_user, guild: guild2, role: :gm, status: :active)
      sign_in guild2_owner_user
    end

    it "allows a non-leader GM to leave and keeps the alliance active with one guild" do
      post leave_alliance_path(alliance)
      expect(response).to redirect_to(dashboard_path)
      ag = AllianceGuild.find_by(alliance: alliance, guild: guild2)
      expect(ag).to be_left
      expect(alliance.reload).to be_active
      expect(alliance.active_guild_count).to eq(1)
    end

    it "prevents the founding guild owner from leaving" do
      sign_in owner
      post leave_alliance_path(alliance)
      expect(response).to redirect_to(alliance_path(alliance))
    end
  end

  describe "POST /alliances/:id/kick_guild" do
    let(:target_owner) do
      u = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      u
    end
    let(:target_guild) { create(:guild, owner: target_owner) }

    before do
      create(:alliance_guild, alliance: alliance, guild: target_guild, status: :active, joined_at: Time.current)
      create(:alliance_member, alliance: alliance, user: target_owner, guild: target_guild, role: :gm, status: :active)
    end

    it "allows a guild custom alliance manager to kick a guild" do
      manager = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: manager, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      create(:guild_member, guild: guild, user: manager, role: :member, status: :active, discord_role_id: "role-manage-alliance")
      guild.update!(permission_role_1_id: "role-manage-alliance", role_1_can_manage_alliance: true)
      create(:alliance_member, alliance: alliance, user: manager, guild: guild, role: :member, status: :active) unless alliance.alliance_members.exists?(user: manager)
      sign_in manager

      post kick_guild_alliance_path(alliance), params: { guild_id: target_guild.id }
      expect(response).to redirect_to(alliance_path(alliance))
      expect(AllianceGuild.find_by(alliance: alliance, guild: target_guild)).to be_kicked
    end

    it "blocks an officer without custom alliance permissions from kicking a guild" do
      officer = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: officer, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      create(:alliance_member, alliance: alliance, user: officer, guild: guild, role: :officer, status: :active)
      sign_in officer

      post kick_guild_alliance_path(alliance), params: { guild_id: target_guild.id }
      expect(response).to redirect_to(alliance_path(alliance))
      expect(AllianceGuild.find_by(alliance: alliance, guild: target_guild)).to be_active
    end
  end
end
