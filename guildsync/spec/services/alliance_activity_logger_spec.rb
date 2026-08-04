# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceActivityLogger do
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

  before do
    create(:alliance_member, alliance: alliance, user: member_user, guild: guild, role: :member, status: :active)
    create(:guild_member, guild: guild, user: member_user, role: :member, status: :active)
  end

  describe ".log" do
    it "records view_action for an active member" do
      expect {
        described_class.log(
          alliance: alliance,
          user: member_user,
          guild: nil,
          view_action: true,
          action_type: "alliance_page_view",
          description: "Viewed test",
          page: "alliances#show"
        )
      }.to change(AllianceActivityLog, :count).by(1)

      log = AllianceActivityLog.order(:id).last
      expect(log.action_type).to eq("alliance_page_view")
      expect(log.metadata["page"]).to eq("alliances#show")
    end

    it "skips view_action for a non-member" do
      outsider = create(:user)
      expect {
        described_class.log(
          alliance: alliance,
          user: outsider,
          guild: nil,
          view_action: true,
          action_type: "alliance_page_view",
          description: "Viewed test"
        )
      }.not_to change(AllianceActivityLog, :count)
    end

    it "records management actions for the alliance leader" do
      expect {
        described_class.log(
          alliance: alliance,
          user: owner,
          guild: guild,
          action_type: "alliance_invite_sent",
          description: "Invited guild X"
        )
      }.to change(AllianceActivityLog, :count).by(1)
    end

    it "skips management actions for a member without privileges" do
      expect {
        described_class.log(
          alliance: alliance,
          user: member_user,
          guild: guild,
          action_type: "alliance_invite_sent",
          description: "Invited guild X"
        )
      }.not_to change(AllianceActivityLog, :count)
    end

    it "records invite_response without alliance membership" do
      invited_owner = create(:user)
      invited_guild = create(:guild, owner: invited_owner)
      expect {
        described_class.log(
          alliance: alliance,
          user: invited_owner,
          guild: invited_guild,
          invite_response: true,
          action_type: "alliance_invite_declined",
          description: "Declined"
        )
      }.to change(AllianceActivityLog, :count).by(1)
    end
  end
end
