# frozen_string_literal: true

require "rails_helper"

RSpec.describe LootRollsChannel, type: :channel do
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let(:loot_roll) { create(:loot_roll, guild: guild, creator: owner) }
  let(:member) { create(:user) }

  before do
    create(:guild_member, guild: guild, user: member, role: :member, status: :active)
  end

  describe ".broadcast_update" do
    it "broadcasts loot_roll_update with entries, winner_id, and has_tie" do
      lr = create(:loot_roll, guild: guild, creator: owner, status: :open)
      e_low = create(:loot_roll_entry, loot_roll: lr, roll_value: 50, display_name: "Low", discord_user_id: "d_low")
      e_high = create(:loot_roll_entry, loot_roll: lr, roll_value: 90, display_name: "High", discord_user_id: "d_high")
      lr.update!(status: :closed, winner_entry: e_high)

      expect(LootRollsChannel).to receive(:broadcast_to).with(
        lr,
        hash_including(
          type:             "loot_roll_update",
          total_entries:    2,
          status:           "closed",
          currently_open:   false,
          winner_id:        e_high.id,
          has_tie:          false,
          entries:         array_including(
            hash_including(id: e_low.id, display_name: "Low", roll_value: 50, is_winner: false),
            hash_including(id: e_high.id, display_name: "High", roll_value: 90, is_winner: true)
          )
        )
      )
      LootRollsChannel.broadcast_update(lr)
    end

    it "masks display_name as Anonymous when the loot roll is anonymous" do
      lr = create(:loot_roll, :anonymous, guild: guild, creator: owner)
      entry = create(
        :loot_roll_entry,
        loot_roll:    lr,
        roll_value:   42,
        display_name: "Secret Player",
        discord_user_id: "d_secret"
      )

      expect(LootRollsChannel).to receive(:broadcast_to).with(
        lr,
        hash_including(
          currently_open: true,
          entries:          array_including(
            hash_including(id: entry.id, display_name: "Anonymous", roll_value: 42)
          )
        )
      )
      LootRollsChannel.broadcast_update(lr)
    end

    it "sets has_tie when multiple active entries share the highest roll" do
      lr = create(:loot_roll, guild: guild, creator: owner)
      create(:loot_roll_entry, loot_roll: lr, roll_value: 99, display_name: "T1", discord_user_id: "t1")
      create(:loot_roll_entry, loot_roll: lr, roll_value: 99, display_name: "T2", discord_user_id: "t2")
      create(:loot_roll_entry, loot_roll: lr, roll_value: 10, display_name: "Low", discord_user_id: "l1")

      expect(LootRollsChannel).to receive(:broadcast_to).with(
        lr,
        hash_including(has_tie: true, currently_open: true)
      )
      LootRollsChannel.broadcast_update(lr)
    end

    it "does not broadcast when loot_roll is nil" do
      expect(LootRollsChannel).not_to receive(:broadcast_to)
      LootRollsChannel.broadcast_update(nil)
    end
  end

  it "confirms subscription for an active guild member" do
    stub_connection(current_user: member)
    subscribe(loot_roll_id: loot_roll.id)
    expect(subscription).to be_confirmed
  end

  it "rejects when the user is not a guild member" do
    stub_connection(current_user: create(:user))
    subscribe(loot_roll_id: loot_roll.id)
    expect(subscription).to be_rejected
  end

  it "rejects when loot_roll_id is zero" do
    stub_connection(current_user: member)
    subscribe(loot_roll_id: 0)
    expect(subscription).to be_rejected
  end

  it "rejects when loot roll does not exist" do
    stub_connection(current_user: member)
    subscribe(loot_roll_id: 999_999_999)
    expect(subscription).to be_rejected
  end
end
