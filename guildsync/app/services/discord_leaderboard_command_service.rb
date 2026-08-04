# frozen_string_literal: true

# Handles the /leaderboard slash command (no subcommands).
# Shows the top 10 guild members by on-time Discord event signup count (DiscordEventSignup).
# The web app Member Leaderboard (`/leaderboard`) uses a separate weighted formula in Guilds::MemberLeaderboardScores.
class DiscordLeaderboardCommandService
  include DiscordCommandHelpers

  def self.handle(interaction)
    new.handle(interaction)
  end

  def handle(interaction)
    result = resolve_guild_and_user(interaction)
    return result if result.is_a?(Hash)

    @guild, @user, @guild_member = result

    # Aggregate on-time signups per Discord user, then resolve to GuildSync users.
    signup_counts = DiscordEventSignup
      .joins(:discord_event)
      .where(discord_events: { guild_id: @guild.id }, status: :on_time)
      .group(:discord_user_id)
      .order("count_all DESC")
      .limit(10)
      .count

    if signup_counts.empty?
      return ephemeral_response(I18n.t("discord.commands.leaderboard.none"))
    end

    # Resolve Discord user IDs to GuildSync user display names
    discord_ids = signup_counts.keys
    user_names  = UserDiscordConnection
      .where(discord_user_id: discord_ids)
      .joins(:user)
      .pluck(:discord_user_id, "users.display_name", "users.username")
      .each_with_object({}) { |(did, dn, un), h| h[did] = dn.presence || un }

    lines = signup_counts.each_with_index.map do |(discord_id, count), index|
      medal = case index
              when 0 then "🥇"
              when 1 then "🥈"
              when 2 then "🥉"
              else       "#{index + 1}."
              end
      name = user_names[discord_id] || discord_id
      "#{medal} **#{name}** — #{count} event#{count == 1 ? '' : 's'}"
    end

    embed = {
      title:       I18n.t("discord.commands.leaderboard.title", guild: @guild.name),
      description: lines.join("\n"),
      color:       0xFFD700,
      footer:      { text: I18n.t("discord.commands.leaderboard.footer") }
    }

    embed_response(embed, ephemeral: true)
  rescue => e
    Rails.logger.error "[DiscordLeaderboardCommand] error: #{e.class}: #{e.message}"
    ephemeral_response(I18n.t("discord.commands.errors.generic"))
  end
end
