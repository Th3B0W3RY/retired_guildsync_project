# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceActivityPolicy do
  include AllianceRequestHelpers

  let(:owner) { create_alliance_paid_user!(:discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active)
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
  end

  describe ".management_actor?" do
    it "is true for the alliance leader user id" do
      expect(described_class.management_actor?(alliance, owner)).to be true
    end

    it "is true for a guild owner in an active alliance guild" do
      g2 = create(:guild)
      create(:alliance_guild, alliance: alliance, guild: g2, status: :active)
      create(:alliance_member, alliance: alliance, user: g2.owner, guild: g2, role: :gm, status: :active)
      expect(described_class.management_actor?(alliance, g2.owner)).to be true
    end

    it "is true for a non-owner with configured alliance manage permissions" do
      expect(described_class.management_actor?(alliance, custom_manager_user)).to be true
    end

    it "is false for a plain member" do
      expect(described_class.management_actor?(alliance, member_user)).to be false
    end

    it "is false for an officer without alliance permission roles" do
      expect(described_class.management_actor?(alliance, officer_user)).to be false
    end
  end

  describe ".active_alliance_member?" do
    it "is true for an active alliance member" do
      expect(described_class.active_alliance_member?(alliance, member_user)).to be true
    end

    it "is false for a user outside the alliance" do
      expect(described_class.active_alliance_member?(alliance, create(:user))).to be false
    end
  end
end
