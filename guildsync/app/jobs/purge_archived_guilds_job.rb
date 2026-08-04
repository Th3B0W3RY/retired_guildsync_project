# frozen_string_literal: true

# Destroys archived guilds whose scheduled_purge_at is due (see Guild::ARCHIVE_RETENTION_PERIOD).
# Enqueued daily from config/initializers/sidekiq.rb when Sidekiq server starts.
class PurgeArchivedGuildsJob < ApplicationJob
  queue_as :default

  def perform
    count = 0
    Guild.purge_ready.find_each do |guild|
      guild.purge!
      count += 1
    end
    Rails.logger.info "[PurgeArchivedGuildsJob] Purged #{count} archived guild(s)." if count.positive?
  end
end
