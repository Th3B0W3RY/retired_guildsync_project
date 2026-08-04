class DiscordUpdateEventParticipantsJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Event.find(event_id)
    guild = event.guild
    discord_setting = guild.guild_discord_setting

    return unless discord_setting&.connected?
    return unless event.discord_message_id.present?

    discord_service = DiscordService.new(bot_token: discord_setting.bot_token)

    # Count participants
    total_participants = event.participants.count + event.discord_event_participations.count

    # Update embed with participant count
    embed = discord_service.create_event_embed(event)
    embed[:fields] << {
      name: "Participants",
      value: "#{total_participants} signed up",
      inline: true
    }

    components = discord_service.create_event_signup_components(event.id)

    begin
      discord_service.update_message(
        discord_setting.events_channel_id,
        event.discord_message_id,
        "🎉 **New Event Created!**",
        embed: embed,
        components: components
      )
    rescue => e
      Rails.logger.error "Failed to update event message: #{e.message}"
      raise
    end
  end
end
