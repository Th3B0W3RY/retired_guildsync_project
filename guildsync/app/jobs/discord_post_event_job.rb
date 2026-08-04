class DiscordPostEventJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Event.find(event_id)
    guild = event.guild
    discord_setting = guild.guild_discord_setting

    return unless discord_setting&.connected?
    return unless discord_setting.events_channel_configured?

    discord_service = DiscordService.new(bot_token: discord_setting.bot_token)

    # Create Discord scheduled event
    begin
      discord_event_data = {
        name: event.title,
        description: event.description || "Join us for this event!",
        scheduled_start_time: event.scheduled_at.iso8601,
        scheduled_end_time: (event.scheduled_at + (event.duration || 60).minutes).iso8601,
        privacy_level: 2, # GUILD_ONLY
        entity_type: 3 # EXTERNAL
      }

      discord_event = discord_service.create_guild_event(
        discord_setting.discord_guild_id,
        discord_event_data
      )

      event.update!(discord_event_id: discord_event["id"])

      # Create embed for channel post
      # Try to get event image if available (from Active Storage or URL)
      image_url = nil
      if event.respond_to?(:image) && event.image.attached?
        image_url = Rails.application.routes.url_helpers.rails_blob_url(event.image, only_path: false)
      elsif event.respond_to?(:image_url) && event.image_url.present?
        image_url = event.image_url
      end

      embed = discord_service.create_event_embed(event, image_url: image_url)
      components = discord_service.create_event_signup_components(event.id)

      # Post to events channel
      message = discord_service.send_message(
        discord_setting.events_channel_id,
        "🎉 **New Event Created!**",
        embed: embed,
        components: components
      )

      event.update!(discord_message_id: message["id"])
    rescue => e
      Rails.logger.error "Failed to post event to Discord: #{e.message}"
      raise
    end
  end
end
