# frozen_string_literal: true

# Deletes guild activity logs older than the retention period (3 months).
# Run daily so that logs are continuously pruned and new logging continues.
class GuildActivityLogPruneJob
  include Sidekiq::Worker

  def perform
    deleted = GuildActivityLog.expired.delete_all
    Rails.logger.info("GuildActivityLogPruneJob: deleted #{deleted} expired log(s)")
  end
end
