# frozen_string_literal: true

# Destroys gear snapshots (Active Storage screenshot + extracted stats) older than
# GearSnapshot::RETENTION_PERIOD_DAYS. Scheduled daily (see config/initializers/sidekiq.rb).
class PurgeExpiredGearSnapshotsJob < ApplicationJob
  queue_as :low

  def perform
    days = GearSnapshot::RETENTION_PERIOD_DAYS
    cutoff = days.days.ago
    purged = 0
    GearSnapshot.past_retention.find_each(batch_size: 250) do |snap|
      snap.destroy!
      purged += 1
    rescue StandardError => e
      Rails.logger.error "[PurgeExpiredGearSnapshotsJob] Failed to destroy GearSnapshot id=#{snap.id}: #{e.class}: #{e.message}"
    end
    Rails.logger.info "[PurgeExpiredGearSnapshotsJob] Purged #{purged} snapshot(s) created before #{cutoff.iso8601} (#{days}-day retention)."
  end
end
