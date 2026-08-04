# frozen_string_literal: true

require "rails_helper"

RSpec.describe LootRollDeadlineJob, type: :job do
  it "closes open loot rolls whose deadline_at is in the past" do
    roll = create(:loot_roll, :with_deadline)
    create(:loot_roll_entry, loot_roll: roll, roll_value: 77, is_reroll: false)
    roll.update!(deadline_at: 2.hours.ago)

    discord_service = instance_double(DiscordLootRollService, update_loot_roll_message: nil)
    allow(DiscordLootRollService).to receive(:new).and_return(discord_service)
    allow(LootRollsChannel).to receive(:broadcast_update)

    described_class.perform_now

    roll.reload
    expect(roll.status).to eq("closed")
    expect(roll.winner_entry&.roll_value).to eq(77)
    expect(DiscordLootRollService).to have_received(:new).with(roll)
    expect(discord_service).to have_received(:update_loot_roll_message)
    expect(LootRollsChannel).to have_received(:broadcast_update).with(roll)
  end

  it "does not touch open loot rolls with a future deadline" do
    roll = create(:loot_roll, :with_deadline)
    create(:loot_roll_entry, loot_roll: roll, roll_value: 10, is_reroll: false)

    allow(DiscordLootRollService).to receive(:new)
    allow(LootRollsChannel).to receive(:broadcast_update)

    described_class.perform_now

    roll.reload
    expect(roll.status).to eq("open")
    expect(DiscordLootRollService).not_to have_received(:new)
    expect(LootRollsChannel).not_to have_received(:broadcast_update)
  end

  it "does not touch open loot rolls with no deadline_at" do
    roll = create(:loot_roll, deadline_at: nil)
    create(:loot_roll_entry, loot_roll: roll, roll_value: 10, is_reroll: false)

    allow(DiscordLootRollService).to receive(:new)
    allow(LootRollsChannel).to receive(:broadcast_update)

    described_class.perform_now

    roll.reload
    expect(roll.status).to eq("open")
    expect(DiscordLootRollService).not_to have_received(:new)
  end

  it "continues processing when Discord update raises" do
    roll_a = create(:loot_roll, :with_deadline)
    create(:loot_roll_entry, loot_roll: roll_a, roll_value: 50, is_reroll: false)
    roll_a.update!(deadline_at: 2.hours.ago)
    roll_b = create(:loot_roll, :with_deadline)
    create(:loot_roll_entry, loot_roll: roll_b, roll_value: 60, is_reroll: false)
    roll_b.update!(deadline_at: 2.hours.ago)

    call_count = 0
    allow(DiscordLootRollService).to receive(:new) do |lr|
      call_count += 1
      svc = instance_double(DiscordLootRollService)
      if lr.id == roll_a.id
        allow(svc).to receive(:update_loot_roll_message).and_raise(StandardError, "discord down")
      else
        allow(svc).to receive(:update_loot_roll_message)
      end
      svc
    end
    allow(LootRollsChannel).to receive(:broadcast_update)

    described_class.perform_now

    expect(roll_a.reload.status).to eq("closed")
    expect(roll_b.reload.status).to eq("closed")
    expect(call_count).to eq(2)
  end
end
