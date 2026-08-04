# frozen_string_literal: true

# Handles the /profile slash command and all its subcommands.
#
# Subcommands (any active guild member):
#   /profile me         — view your own GuildSync profile
#   /profile view user:@User — view another member's profile
class DiscordProfileCommandService
  include DiscordCommandHelpers

  def self.handle(interaction)
    new.handle(interaction)
  end

  def handle(interaction)
    result = resolve_guild_and_user(interaction)
    return result if result.is_a?(Hash)

    @guild, @user, @guild_member = result
    @interaction = interaction

    case subcommand_name(interaction)
    when :me   then handle_me
    when :view then handle_view
    else ephemeral_response(I18n.t("discord.commands.errors.unknown_subcommand"))
    end
  end

  private

  def handle_me
    render_profile_embed(@user, @guild_member)
  end

  def handle_view
    opts              = subcommand_options(@interaction)
    target_discord_id = opts["user"].to_s.strip

    gm = @guild.guild_members.active
               .joins(user: :user_discord_connection)
               .find_by(user_discord_connections: { discord_user_id: target_discord_id })

    if gm.nil?
      return ephemeral_response(I18n.t("discord.commands.profile.not_found"))
    end

    render_profile_embed(gm.user, gm)
  end

  def render_profile_embed(user, gm)
    name       = user.display_name.presence || user.username
    joined     = gm.joined_at ? "<t:#{gm.joined_at.to_i}:D>" : "Unknown"
    event_count = 0

    # Count on-time event participations if data is available
    begin
      discord_conn = user.user_discord_connection
      if discord_conn
        event_count = DiscordEventSignup
          .joins(:discord_event)
          .where(discord_events: { guild_id: @guild.id })
          .where(discord_user_id: discord_conn.discord_user_id, status: :on_time)
          .count
      end
    rescue => e
      Rails.logger.warn "[DiscordProfileCommand] event count error: #{e.message}"
    end

    latest_gear = user.gear_snapshots.where(guild: @guild).order(created_at: :desc).first

    fields = [
      { name: "Guild Role",   value: gm.role.capitalize,                                                   inline: true },
      { name: "Joined",       value: joined,                                                                inline: true },
      { name: "Events (on-time)", value: event_count.to_s,                                                  inline: true },
      { name: "Gear Updated", value: latest_gear ? "<t:#{latest_gear.created_at.to_i}:D>" : "No snapshot", inline: true }
    ]

    embed = {
      title:  I18n.t("discord.commands.profile.title", username: name),
      color:  0x5865F2,
      fields: fields,
      footer: { text: "GuildSync Profile • guild-sync.net" }
    }

    embed_response(embed, ephemeral: true)
  end
end
