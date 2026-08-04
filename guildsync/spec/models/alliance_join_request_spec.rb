# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceJoinRequest, type: :model do
  describe "#accept!" do
    let(:leader) { create(:user) }
    let(:requester) { create(:user) }
    let(:leader_guild) { create(:guild, owner: leader) }
    let(:requesting_guild) { create(:guild, owner: requester) }
    let(:alliance) { create(:alliance, leader_guild: leader_guild, leader_user: leader) }
    let(:join_request) do
      create(:alliance_join_request,
             alliance: alliance,
             requesting_guild: requesting_guild,
             requested_by_user: requester)
    end

    before do
      AllianceGuild.create!(
        alliance: alliance,
        guild: leader_guild,
        status: :active,
        joined_at: Time.current,
        invited_by_user: leader
      )
    end

    it "returns false, rolls back, and adds accept_failed when sync raises" do
      svc = instance_double(AllianceMemberSyncService)
      allow(AllianceMemberSyncService).to receive(:new).and_return(svc)
      allow(svc).to receive(:sync!).and_raise(StandardError.new("sync boom"))

      result = join_request.accept!(leader)

      expect(result).to be(false)
      expect(join_request.errors[:base]).to include(I18n.t("alliances.join_requests.errors.accept_failed"))
      expect(join_request.reload).to be_pending
      expect(AllianceGuild.find_by(alliance: alliance, guild: requesting_guild)).to be_nil
    end
  end
end
