# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AllianceMembers", type: :request do
  let(:owner) { create_alliance_paid_user!(:discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end
  let(:manager) { create_alliance_paid_user!(:discord_auth) }
  let(:regular_member) { create_alliance_paid_user!(:discord_auth) }
  let(:protected_manager) { create_alliance_paid_user!(:discord_auth) }

  before do
    create(:alliance_member, alliance: alliance, user: manager, guild: guild, role: :member, status: :active)
    create(:alliance_member, alliance: alliance, user: regular_member, guild: guild, role: :member, status: :active)
    create(:alliance_member, alliance: alliance, user: protected_manager, guild: guild, role: :member, status: :active)

    create(:guild_member, guild: guild, user: manager, role: :member, status: :active, discord_role_id: "role-manage-alliance")
    create(:guild_member, guild: guild, user: regular_member, role: :member, status: :active)
    create(:guild_member, guild: guild, user: protected_manager, role: :member, status: :active, discord_role_id: "role-manage-alliance")
    guild.update!(permission_role_1_id: "role-manage-alliance", role_1_can_kick_alliance_guilds: true)
  end

  describe "GET /alliances/:alliance_id/alliance_members" do
    it "renders translated index title" do
      sign_in owner
      get alliance_alliance_members_path(alliance)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("alliance_members.index.title"))
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        sign_in owner
        get alliance_alliance_members_path(alliance)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        sign_in owner
        get alliance_alliance_members_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-members-index-support.example/help")
        sign_in owner
        get alliance_alliance_members_path(alliance)
        expect(response.body).to include("https://alliance-members-index-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-members-index-support.example/help")
        sign_in owner
        get alliance_alliance_members_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-members-index-support.example/help")
      end
    end
  end

  describe "DELETE /alliances/:alliance_id/alliance_members/remove" do
    it "allows custom managers to remove regular members" do
      sign_in manager
      target = alliance.alliance_members.find_by(user: regular_member)

      delete remove_alliance_alliance_members_path(alliance), params: { user_id: target.user_id }

      expect(response).to redirect_to(alliance_alliance_members_path(alliance))
      expect(target.reload).to be_removed
    end

    it "blocks custom managers from removing other custom managers" do
      sign_in manager
      target = alliance.alliance_members.find_by(user: protected_manager)

      delete remove_alliance_alliance_members_path(alliance), params: { user_id: target.user_id }

      expect(response).to redirect_to(alliance_alliance_members_path(alliance))
      expect(target.reload).to be_active
    end

    it "blocks custom managers from removing guild owners" do
      sign_in manager
      target = alliance.alliance_members.find_by(user: owner)

      delete remove_alliance_alliance_members_path(alliance), params: { user_id: target.user_id }

      expect(response).to redirect_to(alliance_alliance_members_path(alliance))
      expect(target.reload).to be_active
    end

    it "blocks custom managers from removing members in other guilds" do
      other_owner = create_alliance_paid_user!(:discord_auth)
      other_guild = create(:guild, owner: other_owner)
      create(:alliance_guild, alliance: alliance, guild: other_guild, status: :active)
      other_user = create_alliance_paid_user!(:discord_auth)
      create(:guild_member, guild: other_guild, user: other_user, role: :member, status: :active)
      target = alliance.alliance_members.find_by!(user: other_user)

      sign_in manager
      delete remove_alliance_alliance_members_path(alliance), params: { user_id: target.user_id }

      expect(response).to redirect_to(alliance_alliance_members_path(alliance))
      expect(target.reload).to be_active
    end
  end
end
