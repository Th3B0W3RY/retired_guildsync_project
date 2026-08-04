# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceMemberSyncService, type: :service do
  let(:owner)    { create(:user) }
  let(:guild)    { create(:guild, owner: owner) }
  let(:member1)  { create(:user) }
  let(:inactive_member) { create(:user) }
  let(:alliance) { create(:alliance, leader_guild: guild, leader_user: owner) }

  before do
    create(:guild_member, guild: guild, user: member1, status: :active)
    create(:guild_member, guild: guild, user: inactive_member, status: :inactive)
    create(:alliance_guild, alliance: alliance, guild: guild, status: :active)
  end

  subject(:service) { described_class.new(alliance, guild) }

  describe "#sync!" do
    it "creates AllianceMembers for all guild members and owner" do
      expect { service.sync! }.to change(AllianceMember, :count).by(2)
    end

    it "does not include inactive guild members" do
      service.sync!
      expect(AllianceMember.find_by(alliance: alliance, user: inactive_member)).to be_nil
    end

    it "assigns gm role to guild owner" do
      service.sync!
      gm = AllianceMember.find_by(alliance: alliance, user: owner)
      expect(gm).to be_gm
    end

    it "assigns member role to regular members" do
      service.sync!
      am = AllianceMember.find_by(alliance: alliance, user: member1)
      expect(am).to be_member
    end

    it "marks removed users when they leave the guild" do
      service.sync!
      GuildMember.find_by(guild: guild, user: member1)&.update!(status: :inactive)
      service.sync!
      am = AllianceMember.find_by(alliance: alliance, user: member1)
      expect(am).to be_removed
    end
  end
end
