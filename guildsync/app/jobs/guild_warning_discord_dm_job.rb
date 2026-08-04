# frozen_string_literal: true

class GuildWarningDiscordDmJob < ApplicationJob
  queue_as :default

  def perform(guild_id, user_id, reason, warning_count)
    guild = Guild.find_by(id: guild_id)
    user = User.find_by(id: user_id)
    return unless guild && user

    discord_user_id = user.user_discord_connection&.discord_user_id
    if discord_user_id.blank?
      Rails.logger.info "[GuildWarningDiscordDmJob] Skipping DM guild=#{guild_id} user=#{user_id}: no linked Discord account"
      return
    end

    bot_token = guild.guild_discord_setting&.bot_token.presence || ENV["DISCORD_BOT_TOKEN"].presence
    if bot_token.blank?
      Rails.logger.warn "[GuildWarningDiscordDmJob] Skipping DM guild=#{guild_id}: no bot token configured"
      return
    end

    message = I18n.t(
      "guild_warnings.discord.warning_dm",
      guild_name: guild.name,
      reason: reason.to_s,
      warning_count: warning_count.to_i,
      warning_limit: GuildMemberWarningStatus::WARNING_LIMIT
    )

    DiscordService.new(bot_token: bot_token).send_dm(discord_user_id, message)
    Rails.logger.info "[GuildWarningDiscordDmJob] Sent DM guild=#{guild_id} user=#{user_id} discord_user=#{discord_user_id}"
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "[GuildWarningDiscordDmJob] Discord API guild=#{guild_id} user=#{user_id}: #{e.response&.code} #{e.response&.body}"
  rescue StandardError => e
    Rails.logger.warn "[GuildWarningDiscordDmJob] Failed guild=#{guild_id} user=#{user_id}: #{e.class}: #{e.message}"
  end
end
