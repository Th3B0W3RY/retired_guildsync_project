# frozen_string_literal: true

# Handles the /activity slash command (no subcommands).
# Shows the last 10 guild activity log entries to the invoking user (ephemeral).
class DiscordActivityCommandService
  include DiscordCommandHelpers

  def self.handle(interaction)
    new.handle(interaction)
  end

  def handle(interaction)
    result = resolve_guild_and_user(interaction)
    return result if result.is_a?(Hash)

    @guild, @user, @guild_member = result

    logs = @guild.guild_activity_logs.recent_first.limit(10).includes(:user)

    if logs.empty?
      return ephemeral_response(I18n.t("discord.commands.activity.none"))
    end

    lines = logs.map do |log|
      actor = log.user&.display_name.presence || log.user&.username || "System"
      ts    = "<t:#{log.created_at.to_i}:R>"
      "#{ts} **#{actor}**: #{log.description.truncate(120)}"
    end

    embed = {
      title:       I18n.t("discord.commands.activity.title", guild: @guild.name),
      description: lines.join("\n"),
      color:       0x5865F2,
      footer:      { text: "GuildSync Activity Feed • last 10 entries" }
    }

    embed_response(embed, ephemeral: true)
  rescue => e
    Rails.logger.error "[DiscordActivityCommand] error: #{e.class}: #{e.message}"
    ephemeral_response(I18n.t("discord.commands.errors.generic"))
  end
end
