# frozen_string_literal: true

# Monthly enqueue from config/initializers/sidekiq.rb when DATABASE_BACKUP_TO_S3_ENABLED=1 at boot.
# Performs DatabaseBackupToS3Service (pg_dump + put_object). Misconfiguration is logged, not raised, to avoid retry storms.
class DatabaseBackupToS3Job < ApplicationJob
  queue_as :low

  def perform
    result = DatabaseBackupToS3Service.new.call
    return if result[:disabled]

    if result[:ok] && result[:key].present?
      Rails.logger.info("[DatabaseBackupToS3Job] Uploaded #{result[:key]}")
    elsif result[:error].present?
      Rails.logger.error("[DatabaseBackupToS3Job] #{result[:error]}")
    end
  end
end
