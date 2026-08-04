# frozen_string_literal: true

# Prunes discord_command_executions older than 24 hours.
# Interaction tokens expire after 15 minutes, so rows older than
# a day are pure history with no functional value.
class DiscordCommandExecutionCleanupJob
  include Sidekiq::Worker

  RETENTION_PERIOD = 24.hours

  def perform
    deleted = DiscordCommandExecution.where("created_at < ?", RETENTION_PERIOD.ago).delete_all
    Rails.logger.info("DiscordCommandExecutionCleanupJob: pruned #{deleted} stale execution(s)")
  end
end
