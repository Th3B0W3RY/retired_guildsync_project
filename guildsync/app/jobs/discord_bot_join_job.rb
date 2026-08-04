class DiscordBotJoinJob < ApplicationJob
  queue_as :default

  def perform(guild_id, discord_guild_id)
    guild = Guild.find(guild_id)
    discord_setting = guild.guild_discord_setting

    return unless discord_setting&.bot_token.present?

    # The bot should already be in the server via OAuth invite
    # This job can be used to verify bot presence and update settings
    discord_service = DiscordService.new(bot_token: discord_setting.bot_token)

    begin
      # Try to get guild info to verify bot is in server
      channels = discord_service.get_guild_channels(discord_guild_id)
      discord_setting.update!(connected_at: Time.current) if channels
    rescue => e
      Rails.logger.error "Failed to verify bot in Discord server: #{e.message}"
      raise
    end
  end
end
