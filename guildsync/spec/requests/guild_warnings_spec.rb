# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guild warnings", type: :request do
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

  let(:owner) { create(:user, auth_method: :discord) }
  let(:manager_user) { create(:user, auth_method: :discord) }
  let(:member_user) { create(:user, auth_method: :discord) }
  let(:guild) { create(:guild, owner: owner) }

  # Subscribe before materializing guild/members so `let!` ordering cannot run guild setup on an
  # unsubscribed owner (warnings require `plan_allows?(:warnings)` even for the guild owner).
  before do
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
    [ owner, manager_user, member_user ].each { |u| u.subscribe_to_plan!(basic_plan) }
    create(:guild_member, guild: guild, user: manager_user, status: :active, discord_role_id: "role-1")
    create(:guild_member, guild: guild, user: member_user, status: :active)
    guild.reload.update!(
      permission_role_1_id: "role-1",
      role_1_can_manage_warnings: true
    )
  end

  describe "GET /guilds/:guild_id/warnings/me" do
    it "allows active guild members to view their warning status" do
      sign_in member_user
      get guild_my_warnings_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "denies users who are not in the guild" do
      outsider = create(:user, auth_method: :discord)
      sign_in outsider
      get guild_my_warnings_path(guild)
      expect(response).to redirect_to(my_guilds_path)
    end
  end

  describe "GET /guilds/:guild_id/warnings" do
    it "allows custom manager role access" do
      sign_in manager_user
      get guild_warnings_path(guild)
      expect(response).to have_http_status(:ok)
    end

    it "denies regular members" do
      sign_in member_user
      get guild_warnings_path(guild)
      expect(response).to redirect_to(guild_path(guild))
    end

    it "does not show protected managers in warning selector" do
      sign_in owner
      get guild_warnings_path(guild)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(member_user.display_name)
      expect(response.body).not_to include(manager_user.display_name)
    end
  end

  describe "support_center_url in member chrome" do
    let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

    context "GET /guilds/:id/warnings (managers)" do
      before { sign_in manager_user }

      it "includes default support URL in HTML" do
        get guild_warnings_path(guild)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get guild_warnings_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-warnings-index-support.example/help")
        get guild_warnings_path(guild)
        expect(response.body).to include("https://guild-warnings-index-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-warnings-index-support.example/help")
        get guild_warnings_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-warnings-index-support.example/help")
      end
    end

    context "GET /guilds/:id/warnings/me (members)" do
      before { sign_in member_user }

      it "includes default support URL in HTML" do
        get guild_my_warnings_path(guild)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get guild_my_warnings_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://guild-warnings-my-status-support.example/help")
        get guild_my_warnings_path(guild)
        expect(response.body).to include("https://guild-warnings-my-status-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://guild-warnings-my-status-support.example/help")
        get guild_my_warnings_path(guild), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://guild-warnings-my-status-support.example/help")
      end
    end
  end

  describe "POST /guilds/:guild_id/warnings" do
    before do
      sign_in owner
      create(:user_discord_connection, user: member_user, discord_user_id: "123", discord_username: "member#1234")
      allow(GuildWarningDiscordDmJob).to receive(:perform_later)
    end

    it "creates warning status and increments count" do
      expect {
        post guild_warnings_create_path(guild), params: { user_id: member_user.id, reason: "Be respectful." }
      }.to change { GuildMemberWarningStatus.count }.by(1)

      status = GuildMemberWarningStatus.last
      expect(status.warning_count).to eq(1)
      expect(status).to be_warned
      expect(GuildWarningDiscordDmJob).to have_received(:perform_later).with(guild.id, member_user.id, "Be respectful.", 1)
    end

    it "blocks warnings for protected manager targets" do
      post guild_warnings_create_path(guild), params: { user_id: manager_user.id, reason: "Should be blocked." }

      expect(response).to redirect_to(guild_warnings_path(guild))
      expect(GuildMemberWarningStatus.find_by(guild: guild, user: manager_user)).to be_nil
    end
  end

  describe "PATCH /guilds/:guild_id/warnings/lists" do
    before { sign_in owner }

    it "moves member to banned and sets warning count to 3" do
      create(:guild_member_warning_status, guild: guild, user: member_user, warning_count: 1, state: :warned)

      patch guild_warnings_update_lists_path(guild), params: {
        warning_states: { member_user.id.to_s => "banned" }
      }

      expect(response).to redirect_to(guild_warnings_path(guild))
      status = GuildMemberWarningStatus.find_by!(guild: guild, user: member_user)
      expect(status.warning_count).to eq(3)
      expect(status).to be_banned
    end

    it "does not reclassify protected manager targets" do
      create(:guild_member_warning_status, guild: guild, user: manager_user, warning_count: 1, state: :warned)

      patch guild_warnings_update_lists_path(guild), params: {
        warning_states: { manager_user.id.to_s => "banned" }
      }

      expect(response).to redirect_to(guild_warnings_path(guild))
      status = GuildMemberWarningStatus.find_by!(guild: guild, user: manager_user)
      expect(status.warning_count).to eq(1)
      expect(status).to be_warned
    end
  end

  describe "isolation from other guilds / non-members" do
    let(:outsider) { create(:user, auth_method: :discord) }

    before { outsider.subscribe_to_plan!(basic_plan) }

    it "redirects warnings index when the user has no access to that guild" do
      sign_in outsider
      get guild_warnings_path(guild)
      expect(response).to redirect_to(my_guilds_path)
    end

    it "does not create a warning for a user who is not an active member" do
      sign_in owner
      stray = create(:user, auth_method: :discord)
      stray.subscribe_to_plan!(basic_plan)
      allow(GuildWarningDiscordDmJob).to receive(:perform_later)

      expect {
        post guild_warnings_create_path(guild), params: { user_id: stray.id, reason: "Nope." }
      }.not_to change(GuildMemberWarningStatus, :count)

      expect(response).to redirect_to(guild_warnings_path(guild))
      expect(flash[:alert]).to eq(I18n.t("guild_warnings.alerts.member_not_found"))
    end
  end
end
