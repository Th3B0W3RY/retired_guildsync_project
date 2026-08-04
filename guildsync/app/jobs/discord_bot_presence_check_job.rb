class DiscordBotPresenceCheckJob < ApplicationJob
  queue_as :default

  # This job checks if the GuildSync bot is still present in the GuildSync DEVELOPMENT server
  # It runs every 10 minutes via Sidekiq scheduled jobs
  def perform
    development_server_id = ENV["DISCORD_GUILDSYNC_DEVELOPMENT_SERVER_ID"]
    return unless development_server_id.present?

    bot_token = ENV["DISCORD_BOT_TOKEN"]
    return unless bot_token.present?

    begin
      discord_service = DiscordService.new(bot_token: bot_token)
      
      # Try to get guild info to verify bot is in server
      guild_info = discord_service.get_guild(development_server_id)
      
      Rails.logger.info "Discord bot presence check: Bot is present in GuildSync DEVELOPMENT server (#{guild_info['name']})"
      
      # Update all guilds that use this server
      GuildDiscordSetting.where(discord_guild_id: development_server_id).find_each do |setting|
        setting.update!(connected_at: Time.current)
      end
      
      true
    rescue RestClient::ExceptionWithResponse => e
      if e.response.code == 404
        Rails.logger.error "Discord bot presence check: Bot is NOT in GuildSync DEVELOPMENT server (404 Not Found)"
      elsif e.response.code == 403
        Rails.logger.error "Discord bot presence check: Bot lacks permissions in GuildSync DEVELOPMENT server (403 Forbidden)"
      else
        Rails.logger.error "Discord bot presence check failed: #{e.response.code} - #{e.response.body}"
      end
      false
    rescue => e
      Rails.logger.error "Discord bot presence check failed: #{e.class.name}: #{e.message}"
      false
    end
  end
end

