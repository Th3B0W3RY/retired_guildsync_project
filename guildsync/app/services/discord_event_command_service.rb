# frozen_string_literal: true

require "rest-client"

# Handles the /event slash command and all its subcommands.
#
# Subcommands:
#   /event create title:<str> month:<int> day:<int> hour:<int> minute:<int> ampm:<AM|PM>
#                 [description:<str>] [type:<choice>] [location:<str>] [squad_leader:<str>]
#                 (Year defaults to current/next; Timezone defaults to guild setting)
#   /event list   — upcoming events (ephemeral)
#   /event view   event_id:<int> — event details + signup counts (ephemeral)
#   /event cancel event_id:<int> — cancel event and clean up Discord (officer+)
#
# The existing /signup command (member-facing signup flow) is unchanged.
class DiscordEventCommandService
  include DiscordCommandHelpers

  def self.handle(interaction)
    new.handle(interaction)
  end

  def handle(interaction)
    result = resolve_guild_and_user(interaction)
    return result if result.is_a?(Hash)

    @guild, @user, @guild_member = result
    @interaction = interaction
    @interaction_token = interaction["token"]

    case subcommand_name(interaction)
    when :create then handle_create
    when :list   then handle_list
    when :view   then handle_view
    when :cancel then handle_cancel
    else ephemeral_response(I18n.t("discord.commands.errors.unknown_subcommand"))
    end
  end

  private

  def handle_create
    guard = require_officer!(@guild, @user, @guild_member)
    return guard if guard

    limit_guard = enforce_plan_limit!(@guild, :events)
    return limit_guard if limit_guard

    unless @guild.guild_discord_setting&.events_channel_configured?
      return ephemeral_response(I18n.t("discord.commands.event.no_channel"))
    end

    unless @guild.guild_discord_setting&.connected?
      return ephemeral_response(I18n.t("discord.commands.event.not_connected"))
    end

    opts         = subcommand_options(@interaction)
    title        = opts["title"].to_s.strip
    description  = opts["description"].to_s.strip.presence
    event_type   = opts["type"].to_s.presence || "pvp"
    location     = opts["location"].to_s.strip.presence
    squad_leader = opts["squad_leader"].to_s.strip.presence

    if title.blank?
      return ephemeral_response(I18n.t("discord.commands.event.missing_title"))
    end

    scheduled_at, error = build_datetime_from_options(
      { month: opts["month"], day: opts["day"], hour: opts["hour"],
        minute: opts["minute"], ampm: opts["ampm"] },
      guild: @guild
    )

    return ephemeral_response(error) if error

    interaction_token = @interaction_token
    guild             = @guild
    user              = @user

    DiscordCommandJob.perform_later(
      "DiscordEventCommandService",
      "process_create",
      interaction_token,
      guild.id,
      user.id,
      {
        title: title,
        date: scheduled_at.to_s,
        description: description,
        event_type: event_type,
        location: location,
        squad_leader: squad_leader
      }
    )

    deferred_response(ephemeral: true)
  end

  # Called by DiscordCommandJob
  def process_create(opts)
    discord_setting   = @guild.guild_discord_setting
    events_channel_id = discord_setting.events_channel_id
    bot_token         = discord_setting.bot_token || ENV["DISCORD_BOT_TOKEN"]
    service           = DiscordService.new(bot_token: bot_token)
    scheduled_at      = Time.zone.parse(opts[:date])

    existing = @guild.discord_events.find_by(title: opts[:title], scheduled_at: scheduled_at)
    if existing
      send_followup(
        @interaction_token,
        I18n.t("discord.commands.event.duplicate", title: opts[:title]),
        ephemeral: true
      )
      return
    end

    discord_event_id = service.create_scheduled_event!(
      guild:       @guild,
      channel_id:  events_channel_id,
      name:        opts[:title],
      description: opts[:description],
      start_time:  scheduled_at,
      event_type:  opts[:event_type]
    )

    discord_connection = @guild.discord_connection || DiscordConnection.find_or_create_by!(
      guild: @guild,
      user:  @user
    ) do |c|
      uconn = @user.user_discord_connection
      c.discord_user_id = uconn&.discord_user_id
      c.access_token    = uconn&.access_token
      c.refresh_token   = uconn&.refresh_token
      c.expires_at      = uconn&.expires_at
    end

    default_roles = DiscordEvent::ROLE_CATEGORIES

    discord_event = @guild.discord_events.create!(
      discord_connection: discord_connection,
      discord_event_id:   discord_event_id,
      channel_id:         events_channel_id,
      title:              opts[:title],
      description:        opts[:description],
      event_type:         opts[:event_type],
      scheduled_at:       scheduled_at,
      timezone:           "UTC",
      squad_leader:       opts[:squad_leader],
      location:           opts[:location],
      role_categories:    default_roles
    )

    message_id = service.post_event_signup_message!(discord_event, roles: default_roles)
    discord_event.update!(discord_message_id: message_id) if message_id

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "event_created",
      description: "Created event via Discord: \"#{opts[:title]}\"",
      subject:     discord_event,
      title:       opts[:title]
    )

    send_followup(
      @interaction_token,
      I18n.t("discord.commands.event.created", title: opts[:title]),
      ephemeral: true
    )
  end

  def handle_list
    events = @guild.discord_events
                   .where("scheduled_at > ?", Time.current)
                   .order(scheduled_at: :asc)
                   .limit(10)

    if events.empty?
      return ephemeral_response(I18n.t("discord.commands.event.none_upcoming"))
    end

    lines = events.map do |e|
      ts      = "<t:#{e.scheduled_at.to_i}:F>"
      signups = e.discord_event_signups.where(status: :on_time).count
      "**#{e.id}.** #{e.title} — #{ts} — #{signups} signed up"
    end

    embed = {
      title:       I18n.t("discord.commands.event.list_title", guild: @guild.name),
      description: lines.join("\n"),
      color:       0x5865F2,
      footer:      { text: "GuildSync Events • Use /event view event_id:<id> for details" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_view
    opts     = subcommand_options(@interaction)
    event_id = opts["event_id"].to_i

    event = @guild.discord_events.find_by(id: event_id)
    return ephemeral_response(I18n.t("discord.commands.event.not_found")) unless event

    ts      = "<t:#{event.scheduled_at.to_i}:F>"
    fields  = []

    DiscordEvent::ROLE_CATEGORIES.each do |role|
      count = event.discord_event_signups.where(role: role, status: :on_time).count
      emoji = DiscordEvent::ROLE_EMOJIS[role]
      fields << { name: "#{emoji} #{role.upcase}", value: count.to_s, inline: true }
    end

    fields << { name: "📅 Scheduled", value: ts, inline: false }
    fields << { name: "📍 Location",  value: event.location.presence || "TBD", inline: true }   if event.respond_to?(:location)
    fields << { name: "👤 Squad Leader", value: event.squad_leader.presence || "TBD", inline: true } if event.respond_to?(:squad_leader)

    embed = {
      title:       "🎯 #{event.title}",
      description: event.description.presence || "No description.",
      color:       0x5865F2,
      fields:      fields,
      footer:      { text: "GuildSync Event ##{event.id} • Use /signup role:<role> to sign up" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_cancel
    guard = require_officer!(@guild, @user, @guild_member)
    return guard if guard

    opts     = subcommand_options(@interaction)
    event_id = opts["event_id"].to_i

    event = @guild.discord_events.find_by(id: event_id)
    return ephemeral_response(I18n.t("discord.commands.event.not_found")) unless event

    interaction_token = @interaction_token
    guild             = @guild
    user              = @user

    DiscordCommandJob.perform_later(
      "DiscordEventCommandService",
      "process_cancel",
      interaction_token,
      guild.id,
      user.id,
      { event_id: event.id }
    )

    deferred_response(ephemeral: true)
  end

  # Called by DiscordCommandJob
  def process_cancel(opts)
    event = @guild.discord_events.find_by(id: opts[:event_id])

    # Idempotency: event was already destroyed on a prior attempt
    unless event
      send_followup(
        @interaction_token,
        I18n.t("discord.commands.event.cancelled", title: "(already removed)"),
        ephemeral: true
      )
      return
    end
    discord_setting   = @guild.guild_discord_setting
    bot_token         = discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
    discord_guild_id  = @guild.discord_id || discord_setting&.discord_guild_id

    if discord_guild_id && event.discord_event_id
      begin
        RestClient.delete(
          "#{DiscordService::DISCORD_API_BASE}/guilds/#{discord_guild_id}/scheduled-events/#{event.discord_event_id}",
          { "Authorization" => "Bot #{bot_token}" }
        )
      rescue => e
        Rails.logger.warn "[DiscordEventCommand] Could not delete scheduled event: #{e.message}"
      end
    end

    if event.channel_id && event.discord_message_id
      begin
        DiscordService.new(bot_token: bot_token).delete_message(event.channel_id, event.discord_message_id)
      rescue => e
        Rails.logger.warn "[DiscordEventCommand] Could not delete event message: #{e.message}"
      end
    end

    event_title = event.title
    event.destroy

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "event_deleted",
      description: "Cancelled event via Discord: \"#{event_title}\"",
      title:       event_title
    )

    send_followup(
      @interaction_token,
      I18n.t("discord.commands.event.cancelled", title: event_title),
      ephemeral: true
    )
  end
end
