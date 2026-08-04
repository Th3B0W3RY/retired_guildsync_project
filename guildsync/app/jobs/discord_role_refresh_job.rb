# frozen_string_literal: true

class DiscordRoleRefreshJob
  include Sidekiq::Worker

  def perform
    # Find all guilds with Discord connected and synced roles
    Guild.joins(:guild_discord_setting, :discord_role_syncs)
        .where.not(guild_discord_settings: { discord_guild_id: nil })
        .distinct
        .find_each do |guild|
      refresh_guild_roles(guild)
    end

    Rails.logger.info "DiscordRoleRefreshJob completed successfully"
  rescue => e
    Rails.logger.error "DiscordRoleRefreshJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def refresh_guild_roles(guild)
    discord_setting = guild.guild_discord_setting
    return unless discord_setting&.connected?
    return unless discord_setting.discord_guild_id.present?

    bot_token = discord_setting.bot_token || ENV["DISCORD_BOT_TOKEN"]
    return unless bot_token.present?

    begin
      discord_service = DiscordService.new(bot_token: bot_token)
      live_roles = discord_service.get_guild_roles(discord_setting.discord_guild_id)
      live_role_ids = live_roles.map { |r| r["id"] }.to_set

      # Update role names for existing syncs
      guild.discord_role_syncs.find_each do |sync|
        live_role = live_roles.find { |r| r["id"] == sync.role_id }
        if live_role
          # Update name if it changed
          sync.update!(role_name: live_role["name"]) if sync.role_name != live_role["name"]
        else
          # Role was removed from Discord, remove sync
          Rails.logger.info "Removing sync for deleted Discord role: #{sync.role_name} (#{sync.role_id})"
          sync.destroy
        end
      end

      Rails.logger.info "Refreshed roles for guild: #{guild.name} (#{guild.id})"
    rescue => e
      Rails.logger.error "Failed to refresh roles for guild #{guild.id}: #{e.message}"
      # Don't raise - continue with other guilds
    end
  end
end

