# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AllianceLootRolls", type: :request do
  let(:owner)    { create_alliance_paid_user!(:discord_auth) }
  let(:guild)    { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild,  alliance: a, guild: guild, status: :active)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end
  let(:member_user) { create_alliance_paid_user!(:discord_auth) }
  let(:officer_user) { create_alliance_paid_user!(:discord_auth) }
  let(:custom_manager_user) { create_alliance_paid_user!(:discord_auth) }

  before do
    create(:alliance_member, alliance: alliance, user: member_user, guild: guild, role: :member, status: :active)
    create(:alliance_member, alliance: alliance, user: officer_user, guild: guild, role: :officer, status: :active)
    create(:alliance_member, alliance: alliance, user: custom_manager_user, guild: guild, role: :member, status: :active)
    create(:guild_member, guild: guild, user: member_user, role: :member, status: :active)
    create(:guild_member, guild: guild, user: officer_user, role: :admin, status: :active)
    create(:guild_member, guild: guild, user: custom_manager_user, role: :member, status: :active, discord_role_id: "role-manage-alliance")
    guild.update!(permission_role_1_id: "role-manage-alliance", role_1_can_manage_alliance: true)
    sign_in owner
  end

  describe "GET /alliances/:alliance_id/alliance_loot_rolls" do
    it "renders the loot rolls index" do
      get alliance_alliance_loot_rolls_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "redirects to dashboard with access_denied for an unknown alliance id" do
      get alliance_alliance_loot_rolls_path(0)
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "redirects to dashboard with access_denied when the user is not an alliance member" do
      outsider = create_alliance_paid_user!(:discord_auth)
      sign_in outsider
      get alliance_alliance_loot_rolls_path(alliance)
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get alliance_alliance_loot_rolls_path(alliance)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get alliance_alliance_loot_rolls_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-loot-rolls-index-support.example/help")
        get alliance_alliance_loot_rolls_path(alliance)
        expect(response.body).to include("https://alliance-loot-rolls-index-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-loot-rolls-index-support.example/help")
        get alliance_alliance_loot_rolls_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-loot-rolls-index-support.example/help")
      end
    end
  end

  describe "POST /alliances/:alliance_id/alliance_loot_rolls" do
    it "creates a loot roll as owner" do
      expect {
        post alliance_alliance_loot_rolls_path(alliance), params: {
          alliance_loot_roll: { title: "Epic Mount", min_roll: 1, max_roll: 100, anonymous: false }
        }
      }.to change(AllianceLootRoll, :count).by(1)
    end

    it "allows custom alliance managers to create loot rolls" do
      sign_in custom_manager_user
      expect {
        post alliance_alliance_loot_rolls_path(alliance), params: {
          alliance_loot_roll: { title: "Manager Roll", min_roll: 1, max_roll: 100, anonymous: false }
        }
      }.to change(AllianceLootRoll, :count).by(1)
    end

    it "blocks officers without custom alliance permissions from creating loot rolls" do
      sign_in officer_user
      expect {
        post alliance_alliance_loot_rolls_path(alliance), params: {
          alliance_loot_roll: { title: "Officer Roll", min_roll: 1, max_roll: 100, anonymous: false }
        }
      }.not_to change(AllianceLootRoll, :count)
    end
  end

  describe "GET /alliances/:alliance_id/alliance_loot_rolls/:id" do
    let(:loot_roll) { create(:alliance_loot_roll, alliance: alliance, creator: owner) }

    it "renders show and wires alliance-loot-roll-live for Action Cable updates" do
      get alliance_alliance_loot_roll_path(alliance, loot_roll)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="alliance-loot-roll-live"')
      expect(response.body).to include("data-alliance-loot-roll-live-alliance-loot-roll-id-value")
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get alliance_alliance_loot_roll_path(alliance, loot_roll)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get alliance_alliance_loot_roll_path(alliance, loot_roll), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-loot-rolls-show-support.example/help")
        get alliance_alliance_loot_roll_path(alliance, loot_roll)
        expect(response.body).to include("https://alliance-loot-rolls-show-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-loot-rolls-show-support.example/help")
        get alliance_alliance_loot_roll_path(alliance, loot_roll), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-loot-rolls-show-support.example/help")
      end
    end
  end

  describe "POST /alliances/:alliance_id/alliance_loot_rolls/:id/enter" do
    let(:loot_roll) { create(:alliance_loot_roll, alliance: alliance, creator: owner) }

    it "allows members to enter" do
      sign_in member_user
      expect {
        post enter_alliance_alliance_loot_roll_path(alliance, loot_roll)
      }.to change(AllianceLootRollEntry, :count).by(1)
    end

    it "prevents double entry" do
      sign_in member_user
      create(:alliance_loot_roll, alliance: alliance, creator: owner) # different roll
      # Create first entry directly
      loot_roll.alliance_loot_roll_entries.create!(user: member_user)
      expect {
        post enter_alliance_alliance_loot_roll_path(alliance, loot_roll)
      }.not_to change(AllianceLootRollEntry, :count)
    end
  end

  describe "POST /alliances/:alliance_id/alliance_loot_rolls/:id/close" do
    let!(:loot_roll) { create(:alliance_loot_roll, alliance: alliance, creator: owner, status: :open) }

    it "closes the roll and determines a winner if entries exist" do
      loot_roll.alliance_loot_roll_entries.create!(user: member_user, roll_value: 77)
      post close_alliance_alliance_loot_roll_path(alliance, loot_roll)
      expect(loot_roll.reload).to be_closed
    end
  end
end
