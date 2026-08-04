# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeExpiredGearSnapshotsJob, type: :job do
  let(:owner) { create(:user, :discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:game) { guild.games.first }
  let(:member) do
    u = create(:user, :discord_auth)
    guild.guild_members.create!(user: u, role: :member, status: :active)
    u
  end

  it "destroys snapshots older than GearSnapshot::RETENTION_PERIOD_DAYS and keeps newer ones" do
    old_snap = create(:gear_snapshot, guild: guild, user: member, game: game)
    old_snap.update_column(:created_at, (GearSnapshot::RETENTION_PERIOD_DAYS + 1).days.ago)

    new_snap = create(:gear_snapshot, guild: guild, user: member, game: game)

    described_class.perform_now

    expect(GearSnapshot.exists?(old_snap.id)).to be false
    expect(GearSnapshot.exists?(new_snap.id)).to be true
  end
end
