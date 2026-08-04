# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GearSnapshot, type: :model do
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }
  let(:game) { create(:game) }
  
  describe 'associations' do
    it 'belongs to a guild' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game)
      expect(snapshot.guild).to eq(guild)
    end
    
    it 'belongs to a user' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game)
      expect(snapshot.user).to eq(user)
    end
    
    it 'belongs to a game' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game)
      expect(snapshot.game).to eq(game)
    end
  end
  
  describe 'validations' do
    it 'requires a source' do
      snapshot = build(:gear_snapshot, guild: guild, user: user, game: game, source: nil)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:source]).to be_present
    end
    
    it 'requires data' do
      snapshot = build(:gear_snapshot, guild: guild, user: user, game: game, data: nil)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:data]).to be_present
    end
    
    it 'requires a screenshot to be attached' do
      snapshot = build(:gear_snapshot, guild: guild, user: user, game: game)
      snapshot.screenshot.detach if snapshot.screenshot.attached?
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:screenshot]).to be_present
    end
  end
  
  describe '#status' do
    it 'returns missing for new records' do
      snapshot = GearSnapshot.new
      expect(snapshot.status).to eq('missing')
    end
    
    it 'returns outdated for old snapshots' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game, created_at: 8.days.ago)
      expect(snapshot.status).to eq('outdated')
    end
    
    it 'returns up_to_date for recent snapshots' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game, created_at: 1.day.ago)
      expect(snapshot.status).to eq('up_to_date')
    end
  end
  
  describe "#reference_screenshot_available?" do
    it "is true when a screenshot is attached and within the retention window" do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game)
      expect(snapshot.reference_screenshot_available?).to be true
    end

    it "is false when the record is past the retention period" do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game)
      snapshot.update_column(:created_at, (GearSnapshot::RETENTION_PERIOD_DAYS + 1).days.ago)
      expect(snapshot.reference_screenshot_available?).to be false
    end
  end

  describe '#outdated?' do
    it 'returns true for snapshots older than threshold' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game, created_at: 8.days.ago)
      expect(snapshot.outdated?).to be true
    end
    
    it 'returns false for recent snapshots' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game, created_at: 1.day.ago)
      expect(snapshot.outdated?).to be false
    end
    
    it 'accepts custom threshold' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game, created_at: 3.days.ago)
      expect(snapshot.outdated?(2)).to be true
      expect(snapshot.outdated?(5)).to be false
    end
  end
  
  describe '#key_stats' do
    it 'returns up to three label/value pairs from snapshot data (StatRows order)' do
      snapshot = create(:gear_snapshot,
        guild: guild,
        user: user,
        game: game,
        data: {
          'Gear Score' => 1642,
          'Weapon 1' => 'Shadowblade +10'
        }
      )

      expect(snapshot.key_stats["Gear Score"]).to eq("1642")
      expect(snapshot.key_stats["Weapon 1"]).to eq("Shadowblade +10")
    end

    it 'uses raw hash keys as labels' do
      snapshot = create(:gear_snapshot,
        guild: guild,
        user: user,
        game: game,
        data: {
          'GS' => 1500,
          'Weapon' => 'Sword'
        }
      )

      expect(snapshot.key_stats["GS"]).to eq("1500")
      expect(snapshot.key_stats["Weapon"]).to eq("Sword")
    end

    it 'includes arbitrary keys present in data' do
      snapshot = create(:gear_snapshot,
        guild: guild,
        user: user,
        game: game,
        data: { 'Other Field' => 'Some Value' }
      )

      expect(snapshot.key_stats).to eq({ "Other Field" => "Some Value" })
    end
  end
  
  describe '#last_activity_at' do
    it 'returns nil when timestamps are not set (unsaved record)' do
      snapshot = build(:gear_snapshot, guild: guild, user: user, game: game)
      expect(snapshot).to be_new_record
      expect(snapshot.last_activity_at).to be_nil
    end

    it 'is the later of created_at and updated_at' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game)
      snapshot.update_columns(created_at: 2.days.ago, updated_at: 1.hour.ago)
      snapshot.reload
      expect(snapshot.last_activity_at).to eq(snapshot.updated_at)

      snapshot.update_columns(created_at: 1.day.ago, updated_at: 3.days.ago)
      snapshot.reload
      expect(snapshot.last_activity_at).to eq(snapshot.created_at)
    end
  end

  describe 'after create commit' do
    it 'touches the uploader guild membership' do
      gm = guild.guild_members.find_by!(user: user)
      expect { create(:gear_snapshot, guild: guild, user: user, game: game) }
        .to change { gm.reload.updated_at }
    end

    it 'does not raise when no guild_member row exists for the uploader' do
      orphan_user = create(:user)
      expect { create(:gear_snapshot, guild: guild, user: orphan_user, game: game) }
        .not_to raise_error
    end
  end

  describe '#embedding_vector' do
    it 'returns parsed embedding array' do
      embedding_array = [0.1, 0.2, 0.3, 0.4]
      snapshot = create(:gear_snapshot,
        guild: guild,
        user: user,
        game: game,
        embedding: embedding_array.to_json
      )
      
      expect(snapshot.embedding_vector).to eq(embedding_array)
    end
    
    it 'returns nil when embedding is not present' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game, embedding: nil)
      expect(snapshot.embedding_vector).to be_nil
    end
    
    it 'handles invalid JSON gracefully' do
      snapshot = create(:gear_snapshot, guild: guild, user: user, game: game, embedding: 'invalid json')
      expect(snapshot.embedding_vector).to be_nil
    end
  end
  
  describe 'scopes' do
    let(:other_user) { create(:user) }
    let(:other_guild) { create(:guild, owner: other_user) }
    
    before do
      # Create snapshots for different users and times
      create(:gear_snapshot, guild: guild, user: user, game: game, created_at: 1.day.ago)
      create(:gear_snapshot, guild: guild, user: user, game: game, created_at: 2.days.ago)
      create(:gear_snapshot, guild: guild, user: other_user, game: game, created_at: 1.day.ago)
      create(:gear_snapshot, guild: other_guild, user: user, game: game, created_at: 1.day.ago)
      create(:gear_snapshot, guild: guild, user: user, game: game, created_at: 10.days.ago)
    end
    
    it 'finds latest snapshot for user' do
      latest = GearSnapshot.latest_for_user(guild, user).first
      expect(latest).to be_present
      expect(latest.created_at).to be_within(1.second).of(1.day.ago)
    end
    
    it 'finds recent snapshots' do
      recent = GearSnapshot.recent
      # All 5 snapshots are within 30 days, so all should be found
      expect(recent.count).to eq(5)
    end
    
    it 'finds outdated snapshots' do
      outdated = GearSnapshot.outdated(7)
      expect(outdated.count).to eq(1) # Only the 10-day-old one
    end
  end
end

