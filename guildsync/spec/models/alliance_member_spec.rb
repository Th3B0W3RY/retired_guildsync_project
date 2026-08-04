# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceMember, type: :model do
  let(:user)     { create(:user) }
  let(:guild)    { create(:guild) }
  let(:alliance) { create(:alliance, leader_guild: guild, leader_user: guild.owner) }

  describe "validations" do
    it "prevents duplicate user in same alliance" do
      create(:alliance_member, alliance: alliance, user: user, guild: guild)
      duplicate = build(:alliance_member, alliance: alliance, user: user, guild: guild)
      expect(duplicate).not_to be_valid
    end

    it "prevents active membership in a second alliance" do
      g2 = create(:guild, owner: user)
      other = create(:alliance, leader_guild: g2, leader_user: user)
      create(:alliance_member, alliance: alliance, user: user, guild: guild, status: :active)
      second = build(:alliance_member, alliance: other, user: user, guild: g2, status: :active)
      expect(second).not_to be_valid
      expect(second.errors[:base]).to be_present
    end
  end

  describe "enums" do
    it "has member, officer, and gm roles" do
      expect(AllianceMember.roles.keys).to contain_exactly("member", "officer", "gm")
    end

    it "has active and removed statuses" do
      expect(AllianceMember.statuses.keys).to contain_exactly("active", "removed")
    end
  end

  describe "#role_label" do
    it "returns 'GM' for gm" do
      am = build(:alliance_member, role: :gm)
      expect(am.role_label).to eq("GM")
    end

    it "returns 'Officer' for officer" do
      am = build(:alliance_member, role: :officer)
      expect(am.role_label).to eq("Officer")
    end

    it "returns 'Member' for member" do
      am = build(:alliance_member, role: :member)
      expect(am.role_label).to eq("Member")
    end
  end
end
