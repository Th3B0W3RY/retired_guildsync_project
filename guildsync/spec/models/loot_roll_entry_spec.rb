require 'rails_helper'

RSpec.describe LootRollEntry, type: :model do
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }
  let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

  describe 'associations' do
    it 'belongs to a loot_roll' do
      entry = create(:loot_roll_entry, loot_roll: loot_roll)
      expect(entry.loot_roll).to eq(loot_roll)
    end
  end

  describe 'validations' do
    it 'requires discord_user_id' do
      entry = build(:loot_roll_entry, loot_roll: loot_roll, discord_user_id: nil)
      expect(entry).not_to be_valid
    end

    it 'requires display_name' do
      entry = build(:loot_roll_entry, loot_roll: loot_roll, display_name: nil)
      expect(entry).not_to be_valid
    end

    it 'requires roll_value' do
      entry = build(:loot_roll_entry, loot_roll: loot_roll, roll_value: nil)
      expect(entry).not_to be_valid
    end

    it 'validates uniqueness of discord_user_id per loot_roll (when not a reroll)' do
      create(:loot_roll_entry, loot_roll: loot_roll, discord_user_id: '123456')

      duplicate = build(:loot_roll_entry, loot_roll: loot_roll, discord_user_id: '123456')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:discord_user_id]).to include('You have already rolled.')
    end

    it 'allows same user to roll again after being marked as reroll' do
      original = create(:loot_roll_entry, loot_roll: loot_roll, discord_user_id: '123456')
      original.update!(is_reroll: true)

      new_entry = build(:loot_roll_entry, loot_roll: loot_roll, discord_user_id: '123456')
      expect(new_entry).to be_valid
    end

    it 'validates roll is within bounds' do
      entry = build(:loot_roll_entry, loot_roll: loot_roll, roll_value: 150)
      expect(entry).not_to be_valid
      expect(entry.errors[:roll_value]).to include("must be between #{loot_roll.min_roll} and #{loot_roll.max_roll}")
    end

    it 'validates loot roll is open on create' do
      loot_roll.update!(status: :closed)

      entry = build(:loot_roll_entry, loot_roll: loot_roll)
      expect(entry).not_to be_valid
      expect(entry.errors[:base]).to include('This loot roll is closed.')
    end
  end

  describe 'scopes' do
    it '.active returns entries where is_reroll is false' do
      active_entry = create(:loot_roll_entry, loot_roll: loot_roll, is_reroll: false)
      reroll_entry = create(:loot_roll_entry, loot_roll: loot_roll, is_reroll: true, discord_user_id: 'different')

      expect(LootRollEntry.active).to include(active_entry)
      expect(LootRollEntry.active).not_to include(reroll_entry)
    end

    it '.ordered_by_roll returns entries sorted by roll_value desc, then role_position asc' do
      entry1 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 50, discord_role_position: 5)
      entry2 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_role_position: 2)
      entry3 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_role_position: 5)

      ordered = LootRollEntry.ordered_by_roll
      expect(ordered.first).to eq(entry2) # 90 with position 2
      expect(ordered.second).to eq(entry3) # 90 with position 5
      expect(ordered.last).to eq(entry1) # 50
    end
  end

  describe '#winner?' do
    it 'returns true if this entry is the winner' do
      entry = create(:loot_roll_entry, loot_roll: loot_roll)
      loot_roll.update!(winner_entry: entry)

      expect(entry.winner?).to be true
    end

    it 'returns false if this entry is not the winner' do
      entry = create(:loot_roll_entry, loot_roll: loot_roll)

      expect(entry.winner?).to be false
    end
  end
end
