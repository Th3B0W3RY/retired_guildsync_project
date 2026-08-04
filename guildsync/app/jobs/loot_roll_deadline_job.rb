class LootRollDeadlineJob < ApplicationJob
  queue_as :default

  # This job checks for expired loot rolls and closes them automatically
  # Should be scheduled to run every minute via cron or similar
  def perform
    # Find all open loot rolls with passed deadlines
    expired_rolls = LootRoll.open.where("deadline_at IS NOT NULL AND deadline_at <= ?", Time.current)

    expired_rolls.find_each do |loot_roll|
      begin
        Rails.logger.info "Closing expired loot roll ##{loot_roll.id}: #{loot_roll.title}"

        # Close and determine winner
        loot_roll.close_and_determine_winner!

        # Update Discord message
        begin
          DiscordLootRollService.new(loot_roll).update_loot_roll_message
        rescue => e
          Rails.logger.error "Failed to update Discord message for loot roll ##{loot_roll.id}: #{e.message}"
        end

        # Broadcast via ActionCable
        begin
          LootRollsChannel.broadcast_update(loot_roll)
        rescue => e
          Rails.logger.error "Failed to broadcast update for loot roll ##{loot_roll.id}: #{e.message}"
        end

        Rails.logger.info "Successfully closed loot roll ##{loot_roll.id}. Winner: #{loot_roll.winner_entry&.display_name || 'None'}"
      rescue => e
        Rails.logger.error "Failed to close loot roll ##{loot_roll.id}: #{e.class.name}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
    end

    Rails.logger.info "LootRollDeadlineJob completed. Processed #{expired_rolls.count} expired loot rolls."
  end
end
