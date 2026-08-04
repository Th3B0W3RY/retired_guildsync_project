# frozen_string_literal: true

# Background job to send Discord notifications for gear update requests
# This job sends a DM to the target user requesting a gear update
#
# Usage:
#   DiscordGearRequestJob.perform_later(gear_upload_request_id)
#
# Fallback:
#   If DM fails, attempts to send a mention in the gear channel
class DiscordGearRequestJob < ApplicationJob
  queue_as :default

  def perform(request_id)
    request = GearUploadRequest.find_by(id: request_id)
    return unless request
    
    # Only process pending requests
    return unless request.status == 'pending'
    
    target_user = request.target_user
    guild = request.guild
    requester = request.requester
    
    # Validate required records exist
    return unless target_user && guild && requester
    
    # Find Discord connection for target user
    discord_connection = target_user.user_discord_connection
    return unless discord_connection&.discord_user_id.present?
    
    # Get guild Discord setting to find channel
    guild_setting = guild.guild_discord_setting
    return unless guild_setting&.gear_channel_id.present?
    
    # Build message with link to web page
    requester_name = requester.display_name.presence || requester.username || "A guild manager"
    guild_name = guild.name.presence || "your guild"
    channel_mention = "<##{guild_setting.gear_channel_id}>"
    
    # Build web URL
    web_url = Rails.application.routes.url_helpers.guild_members_gear_url(
      guild,
      host: ENV['HOST'] || ENV['APP_HOST'] || 'localhost:5000'
    )
    
    message = "📸 **Gear Update Requested**\n\n"
    message += "#{requester_name} has requested a gear update from you in **#{guild_name}**.\n\n"
    message += "Upload your gear screenshot:\n"
    message += "- **Web:** #{web_url}\n"
    message += "- **Discord:** Post an image in #{channel_mention} or use `/gear upload`\n\n"
    message += "Thank you!"
    
    # Send DM via Discord API
    begin
      discord_service = DiscordService.new
      discord_service.send_dm(discord_connection.discord_user_id, message)
      Rails.logger.info "Sent gear request DM to #{target_user.display_name} (Discord ID: #{discord_connection.discord_user_id})"
    rescue => e
      Rails.logger.error "Failed to send gear request DM: #{e.message}"
      # Fallback: Send mention in the gear channel
      begin
        discord_service.send_message(
          guild_setting.gear_channel_id,
          "<@#{discord_connection.discord_user_id}> #{message}"
        )
        Rails.logger.info "Sent gear request channel mention for #{target_user.display_name}"
      rescue => e2
        Rails.logger.error "Failed to send gear request mention: #{e2.message}"
      end
    end
  end
end

