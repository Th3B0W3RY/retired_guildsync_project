# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlliancePollsChannel, type: :channel do
  describe ".broadcast_vote_update" do
    let(:owner) { create_alliance_paid_user!(:discord_auth) }
    let(:guild) { create(:guild, owner: owner) }
    let(:alliance) do
      a = create(:alliance, leader_guild: guild, leader_user: owner)
      create(:alliance_guild, alliance: a, guild: guild, status: :active)
      create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
      a
    end
    let(:poll) { create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now, anonymous: false) }

    it "broadcasts vote_update with counts and voters_by_choice" do
      member = create_alliance_paid_user!(:discord_auth)
      create(:alliance_member, alliance: alliance, user: member, guild: guild, role: :member, status: :active)
      poll.alliance_poll_votes.create!(user: member, choice: :yes)

      expect(AlliancePollsChannel).to receive(:broadcast_to).with(
        poll,
        hash_including(
          type: "vote_update",
          vote_counts: hash_including(yes: 1),
          voters_by_choice: hash_including(yes: array_including(member.name_for_discord_embed))
        )
      )
      AlliancePollsChannel.broadcast_vote_update(poll)
    end
  end

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
  let(:poll) { create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now) }

  before do
    create(:alliance_member, alliance: alliance, user: member_user, guild: guild, role: :member, status: :active)
  end

  it "confirms subscription for active alliance members" do
    stub_connection(current_user: member_user)
    subscribe(alliance_poll_id: poll.id)
    expect(subscription).to be_confirmed
  end

  it "rejects when user is not an alliance member" do
    stub_connection(current_user: outsider)
    subscribe(alliance_poll_id: poll.id)
    expect(subscription).to be_rejected
  end

  it "rejects for unknown poll id" do
    stub_connection(current_user: member_user)
    subscribe(alliance_poll_id: 0)
    expect(subscription).to be_rejected
  end
end
