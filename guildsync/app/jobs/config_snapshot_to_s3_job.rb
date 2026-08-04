# frozen_string_literal: true

# Monthly enqueue from config/initializers/sidekiq.rb when CONFIG_SNAPSHOT_TO_S3_ENABLED=1 at Sidekiq boot.
# Uploads a gzipped tar of safe config files + db/schema.rb (see ConfigSnapshotToS3Service).
class ConfigSnapshotToS3Job < ApplicationJob
  queue_as :low

  def perform
    result = ConfigSnapshotToS3Service.new.call
    return if result[:disabled]

    if result[:ok] && result[:key].present?
      Rails.logger.info("[ConfigSnapshotToS3Job] Uploaded #{result[:key]}")
    elsif result[:error].present?
      Rails.logger.error("[ConfigSnapshotToS3Job] #{result[:error]}")
    end
  end
end
