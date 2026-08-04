# frozen_string_literal: true

# Background job to process bulk gear requests
# This job handles sending notifications for multiple gear requests at once,
# with rate limiting to avoid Discord API rate limits
#
# Usage:
#   DiscordBulkGearRequestJob.perform_later(guild_id, requester_id, [user_id1, user_id2, ...])
#
# Rate Limiting:
#   - Processes requests with 1 second delay between each
#   - Respects Discord API rate limits (50 requests/second per endpoint)
class DiscordBulkGearRequestJob < ApplicationJob
  queue_as :default
  
  def perform(guild_id, requester_id, target_user_ids = nil)
    guild = Guild.find_by(id: guild_id)
    requester = User.find_by(id: requester_id)
    
    unless guild && requester
      Rails.logger.error "DiscordBulkGearRequestJob: Invalid guild_id or requester_id"
      return
    end
    
    # Get pending requests for this guild
    # If target_user_ids provided, only process those (from bulk request)
    query = GearUploadRequest.where(guild: guild, status: :pending)
    query = query.where(target_user_id: target_user_ids) if target_user_ids.present?
    query = query.where('created_at > ?', 1.hour.ago) # Only recent bulk requests
    
    pending_requests = query.to_a
    
    if pending_requests.empty?
      Rails.logger.info "DiscordBulkGearRequestJob: No pending requests found for guild #{guild_id}"
      return
    end
    
    Rails.logger.info "DiscordBulkGearRequestJob: Processing #{pending_requests.count} gear requests for guild #{guild_id}"
    
    # Send notifications (rate limited)
    success_count = 0
    error_count = 0
    
    pending_requests.each do |request|
      begin
        DiscordGearRequestJob.perform_later(request.id)
        success_count += 1
        sleep(1) # Rate limit: 1 per second (conservative for Discord API)
      rescue => e
        error_count += 1
        Rails.logger.error "DiscordBulkGearRequestJob: Failed to enqueue request #{request.id}: #{e.message}"
      end
    end
    
    Rails.logger.info "DiscordBulkGearRequestJob: Completed - #{success_count} enqueued, #{error_count} errors"
  end
end

