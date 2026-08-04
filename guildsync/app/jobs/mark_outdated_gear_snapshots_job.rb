# frozen_string_literal: true

# Background job to check for outdated gear snapshots
# This job doesn't actually mark records - status is calculated dynamically
# But it can be used to send notifications or generate reports
#
# Scheduled: Every 30 minutes (see config/initializers/sidekiq.rb)
#
# Retention: PurgeExpiredGearSnapshotsJob removes snapshots (image + stats) older than
# GearSnapshot::RETENTION_PERIOD_DAYS. This job only reports "outdated" relative to the
# product's 7-day freshness threshold.
class MarkOutdatedGearSnapshotsJob < ApplicationJob
  queue_as :default
  
  def perform(threshold_days = 7)
    Rails.logger.info "Starting outdated gear snapshots check (threshold: #{threshold_days} days)"
    
    # Count outdated snapshots
    outdated_count = GearSnapshot.outdated(threshold_days).count
    Rails.logger.info "Found #{outdated_count} outdated gear snapshots (older than #{threshold_days} days)"
    
    # Optional: Send summary to guild owners
    # This can be enabled in the future for notifications
    # Guild.find_each do |guild|
    #   outdated = GearSnapshot.where(guild: guild).outdated(threshold_days).count
    #   if outdated > 0
    #     # Send notification to guild owner
    #   end
    # end
    
    outdated_count
  end
end

