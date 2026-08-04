# frozen_string_literal: true

require "rails_helper"

RSpec.describe FreePlanDowngradeSideEffects, type: :service do
  describe ".call" do
    it "no-ops when user is nil" do
      expect { described_class.call(user: nil) }.not_to change(AllianceGuild, :count)
    end

    it "does not write snapshot when user has no owned guilds in an alliance" do
      owner = create(:user)
      create(:guild, owner: owner)

      described_class.call(user: owner)

      expect(owner.reload.alliance_downgrade_snapshot).to eq({})
    end

    context "when an owned guild is the alliance leader and another guild remains" do
      let(:leader_owner) { create(:user) }
      let(:leader_guild) { create(:guild, owner: leader_owner) }
      let(:other_owner) { create(:user) }
      let(:other_guild) { create(:guild, owner: other_owner) }
      let!(:alliance) do
        create(:alliance,
          name: "Downgrade spec alliance",
          leader_guild: leader_guild,
          leader_user: leader_owner,
          status: :active)
      end
      let!(:ag_leader) do
        create(:alliance_guild, alliance: alliance, guild: leader_guild, status: :active, joined_at: 2.days.ago)
      end
      let!(:ag_other) do
        create(:alliance_guild, alliance: alliance, guild: other_guild, status: :active, joined_at: 1.day.ago)
      end
      let!(:leader_owner_alliance_member) do
        AllianceMemberSyncService.new(alliance, leader_guild).sync!
        AllianceMember.find_by!(alliance: alliance, user: leader_owner, guild: leader_guild)
      end

      it "marks leader alliance_guild left, promotes successor, removes alliance_members for that guild, stores snapshot" do
        described_class.call(user: leader_owner)

        expect(ag_leader.reload.status).to eq("left")
        expect(ag_other.reload.status).to eq("active")

        alliance.reload
        expect(alliance.leader_guild_id).to eq(other_guild.id)
        expect(alliance.leader_user_id).to eq(other_owner.id)

        expect(leader_owner_alliance_member.reload.status).to eq("removed")

        snap = leader_owner.reload.alliance_downgrade_snapshot
        expect(snap["alliance_ids"]).to eq([ alliance.id ])
        expect(snap["removed_at"]).to be_present
      end
    end

    context "when an owned guild is in the alliance but is not the leader" do
      let(:leader_owner) { create(:user) }
      let(:leader_guild) { create(:guild, owner: leader_owner) }
      let(:member_owner) { create(:user) }
      let(:member_guild) { create(:guild, owner: member_owner) }
      let!(:alliance) do
        create(:alliance,
          name: "Downgrade spec alliance 2",
          leader_guild: leader_guild,
          leader_user: leader_owner,
          status: :active)
      end
      let!(:ag_leader) do
        create(:alliance_guild, alliance: alliance, guild: leader_guild, status: :active, joined_at: 3.days.ago)
      end
      let!(:ag_member) do
        create(:alliance_guild, alliance: alliance, guild: member_guild, status: :active, joined_at: 2.days.ago)
      end
      let!(:am_member) do
        create(:alliance_member, alliance: alliance, user: member_owner, guild: member_guild, status: :active)
      end

      it "removes only that guild from the alliance without changing alliance leadership" do
        described_class.call(user: member_owner)

        expect(ag_member.reload.status).to eq("left")
        expect(ag_leader.reload.status).to eq("active")

        alliance.reload
        expect(alliance.leader_guild_id).to eq(leader_guild.id)
        expect(alliance.leader_user_id).to eq(leader_owner.id)

        expect(am_member.reload.status).to eq("removed")

        snap = member_owner.reload.alliance_downgrade_snapshot
        expect(snap["alliance_ids"]).to eq([ alliance.id ])
      end
    end
  end
end
