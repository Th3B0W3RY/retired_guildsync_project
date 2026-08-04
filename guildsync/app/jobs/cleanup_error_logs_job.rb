# frozen_string_literal: true

# Deletes resolved error logs older than 30 days. Run daily via cron/Sidekiq.
class CleanupErrorLogsJob < ApplicationJob
  queue_as :low

  RETENTION_DAYS = 30

  def perform
    cutoff = RETENTION_DAYS.days.ago
    deleted = ErrorLog.resolved.where("resolved_at < ?", cutoff).delete_all
    Rails.logger.info "[CleanupErrorLogsJob] Deleted #{deleted} resolved error logs older than #{RETENTION_DAYS} days."
  end
end
