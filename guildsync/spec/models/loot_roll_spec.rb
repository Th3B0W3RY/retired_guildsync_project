require 'rails_helper'

RSpec.describe LootRoll, type: :model do
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }

  describe 'associations' do
    it 'belongs to a guild' do
      loot_roll = create(:loot_roll, guild: guild, creator: user)
      expect(loot_roll.guild).to eq(guild)
    end

    it 'belongs to a creator (user)' do
      loot_roll = create(:loot_roll, guild: guild, creator: user)
      expect(loot_roll.creator).to eq(user)
    end

    it 'has many loot_roll_entries' do
      loot_roll = create(:loot_roll, guild: guild, creator: user)
      entry = create(:loot_roll_entry, loot_roll: loot_roll)
      expect(loot_roll.loot_roll_entries).to include(entry)
    end

    it 'destroys entries when destroyed' do
      loot_roll = create(:loot_roll, guild: guild, creator: user)
      create(:loot_roll_entry, loot_roll: loot_roll)
      expect { loot_roll.destroy }.to change(LootRollEntry, :count).by(-1)
    end

    it 'can have an optional winner_entry' do
      loot_roll = create(:loot_roll, guild: guild, creator: user)
      entry = create(:loot_roll_entry, loot_roll: loot_roll)
      loot_roll.update!(winner_entry: entry)
      expect(loot_roll.winner_entry).to eq(entry)
    end
  end

  describe 'validations' do
    it 'requires a title' do
      loot_roll = build(:loot_roll, guild: guild, creator: user, title: nil)
      expect(loot_roll).not_to be_valid
      expect(loot_roll.errors[:title]).to be_present
    end

    it 'validates title length' do
      loot_roll = build(:loot_roll, guild: guild, creator: user, title: 'a' * 256)
      expect(loot_roll).not_to be_valid
    end

    it 'requires min_roll' do
      loot_roll = build(:loot_roll, guild: guild, creator: user, min_roll: nil)
      expect(loot_roll).not_to be_valid
    end

    it 'requires max_roll' do
      loot_roll = build(:loot_roll, guild: guild, creator: user, max_roll: nil)
      expect(loot_roll).not_to be_valid
    end

    it 'validates max_roll is greater than min_roll' do
      loot_roll = build(:loot_roll, guild: guild, creator: user, min_roll: 100, max_roll: 50)
      expect(loot_roll).not_to be_valid
      expect(loot_roll.errors[:max_roll]).to include('must be greater than minimum roll')
    end
  end

  describe '#currently_open?' do
    it 'returns true when status is open and no deadline' do
      loot_roll = create(:loot_roll, guild: guild, creator: user, status: :open, deadline_at: nil)
      expect(loot_roll.currently_open?).to be true
    end

    it 'returns true when status is open and deadline is in the future' do
      loot_roll = create(:loot_roll, guild: guild, creator: user, status: :open, deadline_at: 1.hour.from_now)
      expect(loot_roll.currently_open?).to be true
    end

    it 'returns false when status is open but deadline has passed' do
      loot_roll = create(:loot_roll, guild: guild, creator: user, status: :open, deadline_at: 1.hour.ago)
      expect(loot_roll.currently_open?).to be false
    end

    it 'returns false when status is closed' do
      loot_roll = create(:loot_roll, guild: guild, creator: user, status: :closed)
      expect(loot_roll.currently_open?).to be false
    end
  end

  describe ".open_for_participation" do
    it "includes only open-status rolls with no deadline or a future deadline" do
      still_open = create(:loot_roll, guild: guild, creator: user, status: :open, deadline_at: nil)
      future_deadline = create(:loot_roll, :with_deadline, guild: guild, creator: user, status: :open)
      create(:loot_roll, guild: guild, creator: user, status: :open, deadline_at: 1.hour.ago)
      create(:loot_roll, :closed, guild: guild, creator: user)

      expect(described_class.open_for_participation).to contain_exactly(still_open, future_deadline)
    end
  end

  describe '#determine_winner' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'returns the entry with the highest roll' do
      entry1 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 50)
      entry2 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90)
      entry3 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 75)

      expect(loot_roll.determine_winner).to eq(entry2)
    end

    it 'uses role position as tie-breaker (lower position = higher rank wins)' do
      entry1 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_role_position: 5)
      entry2 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_role_position: 2)

      expect(loot_roll.determine_winner).to eq(entry2)
    end

    it 'excludes entries marked as reroll' do
      entry1 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 100, is_reroll: true)
      entry2 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 50)

      expect(loot_roll.determine_winner).to eq(entry2)
    end
  end

  describe '#close_and_determine_winner!' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'closes the loot roll and sets the winner' do
      entry = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 75)

      loot_roll.close_and_determine_winner!

      expect(loot_roll.reload.status).to eq('closed')
      expect(loot_roll.winner_entry).to eq(entry)
    end

    it 'starts tiebreaker when there is a tie' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user2')

      loot_roll.close_and_determine_winner!

      expect(loot_roll.reload.status).to eq('open') # Still open for tiebreaker
      expect(loot_roll.current_tiebreaker_round).to eq(1)
      expect(loot_roll.tied_discord_user_ids).to contain_exactly('user1', 'user2')
    end
  end

  describe '#has_tie?' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'returns false when there are no entries' do
      expect(loot_roll.has_tie?).to be false
    end

    it 'returns false when there is only one entry' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 75)
      expect(loot_roll.has_tie?).to be false
    end

    it 'returns false when entries have different values' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 75, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 85, discord_user_id: 'user2')
      expect(loot_roll.has_tie?).to be false
    end

    it 'returns true when multiple entries have the highest roll' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user2')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 50, discord_user_id: 'user3')
      expect(loot_roll.has_tie?).to be true
    end

    it 'ignores rerolled entries' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user1', is_reroll: true)
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user2')
      expect(loot_roll.has_tie?).to be false
    end
  end

  describe '#tied_user_ids' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'returns empty array when no tie' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 80, discord_user_id: 'user2')
      expect(loot_roll.tied_user_ids).to eq([])
    end

    it 'returns user ids of tied entries' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user2')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 50, discord_user_id: 'user3')
      expect(loot_roll.tied_user_ids).to contain_exactly('user1', 'user2')
    end
  end

  describe '#start_tiebreaker!' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'increments the tiebreaker round' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user2')

      expect { loot_roll.start_tiebreaker! }.to change { loot_roll.current_tiebreaker_round }.from(0).to(1)
    end

    it 'stores the tied user ids' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user2')

      loot_roll.start_tiebreaker!

      expect(loot_roll.tied_discord_user_ids).to contain_exactly('user1', 'user2')
    end
  end

  describe '#check_tiebreaker_complete!' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    before do
      @entry1 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user1')
      @entry2 = create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user2')
      loot_roll.start_tiebreaker!
    end

    it 'does nothing if not all users have rerolled' do
      @entry1.update!(tiebreaker_round: 1, roll_value: 85)
      # entry2 hasn't rerolled yet

      loot_roll.check_tiebreaker_complete!

      expect(loot_roll.reload.status).to eq('open')
    end

    it 'closes and determines winner when all users rerolled and no tie' do
      @entry1.update!(tiebreaker_round: 1, roll_value: 85)
      @entry2.update!(tiebreaker_round: 1, roll_value: 70)

      loot_roll.check_tiebreaker_complete!

      expect(loot_roll.reload.status).to eq('closed')
      expect(loot_roll.winner_entry).to eq(@entry1)
    end

    it 'starts another tiebreaker if still tied after rerolls' do
      @entry1.update!(tiebreaker_round: 1, roll_value: 80)
      @entry2.update!(tiebreaker_round: 1, roll_value: 80)

      loot_roll.check_tiebreaker_complete!

      expect(loot_roll.reload.status).to eq('open')
      expect(loot_roll.current_tiebreaker_round).to eq(2)
    end
  end

  describe '#in_tiebreaker?' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'returns false when no tiebreaker in progress' do
      expect(loot_roll.in_tiebreaker?).to be false
    end

    it 'returns true when tiebreaker is active' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user2')
      loot_roll.start_tiebreaker!

      expect(loot_roll.in_tiebreaker?).to be true
    end
  end

  describe '#total_entries' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'counts only active entries (not rerolls)' do
      create(:loot_roll_entry, loot_roll: loot_roll, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, discord_user_id: 'user2')
      create(:loot_roll_entry, loot_roll: loot_roll, discord_user_id: 'user3', is_reroll: true)

      expect(loot_roll.total_entries).to eq(2)
    end
  end

  describe '#highest_roll' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'returns the highest roll value among active entries' do
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 50, discord_user_id: 'user1')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 90, discord_user_id: 'user2')
      create(:loot_roll_entry, loot_roll: loot_roll, roll_value: 100, discord_user_id: 'user3', is_reroll: true)

      expect(loot_roll.highest_roll).to eq(90)
    end

    it 'returns nil when no entries' do
      expect(loot_roll.highest_roll).to be_nil
    end
  end

  describe '#expired?' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'returns false when no deadline' do
      expect(loot_roll.expired?).to be false
    end

    it 'returns false when deadline is in the future' do
      loot_roll.update!(deadline_at: 1.hour.from_now)
      expect(loot_roll.expired?).to be false
    end

    it 'returns true when deadline has passed' do
      loot_roll.update!(deadline_at: 1.hour.ago)
      expect(loot_roll.expired?).to be true
    end
  end

  describe '#time_remaining' do
    let(:loot_roll) { create(:loot_roll, guild: guild, creator: user) }

    it 'returns nil when no deadline' do
      expect(loot_roll.time_remaining).to be_nil
    end

    it 'returns 0 when deadline has passed' do
      loot_roll.update!(deadline_at: 1.hour.ago)
      expect(loot_roll.time_remaining).to eq(0)
    end

    it 'returns positive number when deadline is in future' do
      loot_roll.update!(deadline_at: 1.hour.from_now)
      expect(loot_roll.time_remaining).to be > 0
    end
  end
end
