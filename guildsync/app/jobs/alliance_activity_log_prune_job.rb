# frozen_string_literal: true

# Deletes alliance activity logs older than RETENTION_DAYS (60).
class AllianceActivityLogPruneJob
  include Sidekiq::Worker

  def perform
    deleted = AllianceActivityLog.expired.delete_all
    Rails.logger.info("AllianceActivityLogPruneJob: deleted #{deleted} expired log(s)")
  end
end
