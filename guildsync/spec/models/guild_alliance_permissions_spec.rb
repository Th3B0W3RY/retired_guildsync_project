# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guild, type: :model do
  describe "alliance permission sync callback" do
    let(:owner) { create(:user) }
    let(:guild) { create(:guild, owner: owner) }
    let(:alliance) { create(:alliance, leader_guild: guild, leader_user: owner) }
    let(:sync_service) { instance_double(AllianceMemberSyncService, sync!: true) }

    before do
      create(:alliance_guild, alliance: alliance, guild: guild, status: :active)
      allow(AllianceMemberSyncService).to receive(:new).and_return(sync_service)
    end

    it "syncs alliance members when alliance permission settings change" do
      guild.update!(role_1_can_manage_alliance: true)

      expect(AllianceMemberSyncService).to have_received(:new).with(alliance, guild)
      expect(sync_service).to have_received(:sync!)
    end
  end
end
