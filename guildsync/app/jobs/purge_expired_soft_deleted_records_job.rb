# frozen_string_literal: true

# Permanently destroys SoftDeletable rows whose +deleted_at+ is older than
# SoftDeletable::RETENTION_PERIOD, mirroring admin manual purge (+destroy!+ so
# model callbacks and attachment cleanup run).
#
# Order tries to purge dependent rows first (comments before requests, files before folders).
class PurgeExpiredSoftDeletedRecordsJob
  include Sidekiq::Worker

  sidekiq_options retry: 3, queue: "default"

  CLASS_PURGE_ORDER = %w[
    FeatureRequestComment
    FileEntry
    Folder
    GuildDocument
    Event
    DiscordEvent
    Poll
    LootRoll
    AllianceEvent
    AlliancePoll
    AllianceLootRoll
    LandingUserFeedback
    HomepageFeatureCard
    FeatureRequest
  ].freeze

  def perform
    cutoff = SoftDeletable::RETENTION_PERIOD.ago
    total_ok = 0
    total_failed = 0

    ordered_registry_classes.each do |klass|
      klass.deleted.where("#{klass.table_name}.deleted_at < ?", cutoff).find_each do |record|
        record.destroy!
        total_ok += 1
      rescue StandardError => e
        total_failed += 1
        Rails.logger.error(
          "[PurgeExpiredSoftDeletedRecordsJob] #{klass.name}##{record.id} #{e.class}: #{e.message}"
        )
      end
    end

    Rails.logger.info(
      "[PurgeExpiredSoftDeletedRecordsJob] completed ok=#{total_ok} failed=#{total_failed} cutoff=#{cutoff.iso8601}"
    )
  end

  private

  def ordered_registry_classes
    by_name = SoftDeletedRecordRegistry::RECORD_TYPES
    ordered = CLASS_PURGE_ORDER.filter_map { |name| by_name[name] }
    ordered + (SoftDeletedRecordRegistry.classes - ordered)
  end
end
