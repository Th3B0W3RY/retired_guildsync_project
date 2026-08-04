# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceMessagesChannel, type: :channel do
  let(:owner) { create_alliance_paid_user!(:discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end
  let(:member_user) { create_alliance_paid_user!(:discord_auth) }
  let(:outsider) { create_alliance_paid_user!(:discord_auth) }

  before do
    create(:alliance_member, alliance: alliance, user: member_user, guild: guild, role: :member, status: :active)
  end

  context "when subscribed as alliance member (all_members)" do
    before { stub_connection(current_user: member_user) }

    it "confirms subscription" do
      subscribe(alliance_id: alliance.id, message_type: "all_members")
      expect(subscription).to be_confirmed
    end
  end

  context "when user is not an alliance member" do
    before { stub_connection(current_user: outsider) }

    it "rejects subscription" do
      subscribe(alliance_id: alliance.id, message_type: "all_members")
      expect(subscription).to be_rejected
    end
  end

  context "when gm_only stream" do
    it "rejects non-GM members" do
      stub_connection(current_user: member_user)
      subscribe(alliance_id: alliance.id, message_type: "gm_only")
      expect(subscription).to be_rejected
    end

    it "allows guild owners in the alliance" do
      stub_connection(current_user: owner)
      subscribe(alliance_id: alliance.id, message_type: "gm_only")
      expect(subscription).to be_confirmed
    end
  end

  context "when message_type is invalid" do
    before { stub_connection(current_user: member_user) }

    it "rejects" do
      subscribe(alliance_id: alliance.id, message_type: "nope")
      expect(subscription).to be_rejected
    end
  end

  context "when alliance_id is invalid" do
    before { stub_connection(current_user: member_user) }

    it "rejects zero" do
      subscribe(alliance_id: 0, message_type: "all_members")
      expect(subscription).to be_rejected
    end

    it "rejects missing alliance" do
      subscribe(alliance_id: 999_999_999, message_type: "all_members")
      expect(subscription).to be_rejected
    end
  end
end
