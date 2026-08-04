# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildMember, type: :model do
  describe "alliance sync callback" do
    let(:owner) { create(:user) }
    let(:guild) { create(:guild, owner: owner) }
    let(:alliance) { create(:alliance, leader_guild: guild, leader_user: owner) }
    let(:sync_service) { instance_double(AllianceMemberSyncService, sync!: true) }

    before do
      create(:alliance_guild, alliance: alliance, guild: guild, status: :active)
      allow(AllianceMemberSyncService).to receive(:new).and_return(sync_service)
    end

    it "syncs alliance members after guild member create" do
      create(:guild_member, guild: guild, user: create(:user), status: :active)

      expect(AllianceMemberSyncService).to have_received(:new).with(alliance, guild)
      expect(sync_service).to have_received(:sync!)
    end
  end
end
