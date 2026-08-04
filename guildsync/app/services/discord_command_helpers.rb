# frozen_string_literal: true

# Shared utility module included by every Discord slash-command service class.
# Provides:
#   - Guild / user resolution from an interaction payload
#   - Tiered permission guards (member, officer, owner)
#   - Subscription plan limit enforcement
#   - Canonical ephemeral / non-ephemeral response builders
#   - Deferred-response helpers for slow operations
#
# All public helper methods return a Discord interaction response hash on
# failure (so the caller can return it immediately) or nil on success.
module DiscordCommandHelpers
  DISCORD_API_BASE = "https://discord.com/api/v10"
  EPHEMERAL_FLAG   = 64

  # =========================================================================
  # Resolution helpers
  # =========================================================================

  # Resolve the GuildSync Guild and User from a Discord interaction payload.
  #
  # Returns [guild, user, guild_member] on success.
  # Returns an error response hash when resolution fails.
  def resolve_guild_and_user(interaction)
    guild_discord_id = interaction["guild_id"]
    member_data      = interaction["member"]
    user_discord_id  = member_data&.dig("user", "id")

    unless guild_discord_id && user_discord_id
      return error_response(I18n.t("discord.commands.errors.server_only"))
    end

    guild = Guild.joins(:guild_discord_setting)
                 .find_by(guild_discord_settings: { discord_guild_id: guild_discord_id })

    unless guild
      return error_response(I18n.t("discord.commands.errors.guild_not_linked"))
    end

    user = User.joins(:user_discord_connection)
               .find_by(user_discord_connections: { discord_user_id: user_discord_id })

    unless user
      return error_response(I18n.t("discord.commands.errors.user_not_linked"))
    end

    guild_member = guild.guild_members.find_by(user: user, status: :active)

    unless guild_member
      return error_response(I18n.t("discord.commands.errors.not_a_member"))
    end

    [guild, user, guild_member]
  end

  # =========================================================================
  # Permission guards — return an error response or nil
  # =========================================================================

  # Require at least officer-level access (moderator, admin, or owner).
  # guild_member can also satisfy via Discord role-based permission flags
  # configured in guild settings.
  def require_officer!(guild, user, guild_member)
    return nil if guild_owner?(guild, user)
    return nil if guild_officer_by_role?(guild, user, guild_member)

    error_response(I18n.t("discord.commands.errors.officer_required"))
  end

  # Require guild ownership.
  def require_owner!(guild, user)
    return nil if guild_owner?(guild, user)

    error_response(I18n.t("discord.commands.errors.owner_required"))
  end

  # =========================================================================
  # Plan limit guard
  # =========================================================================

  # Returns nil if the plan allows the feature, error response otherwise.
  # Supported feature symbols: :polls, :loot_rolls, :events, :gear
  def enforce_plan_limit!(guild, feature)
    plan = guild.owner&.current_plan
    return error_response(I18n.t("discord.commands.errors.no_plan")) unless plan

    case feature
    when :polls
      limit = plan.max_polls
      return nil if limit.nil? || limit <= 0
      current = guild.polls.count
      if current >= limit
        return error_response(
          I18n.t("discord.commands.errors.plan_limit",
                 feature: "polls", limit: limit, plan: plan.name)
        )
      end
    when :loot_rolls
      limit = plan.max_loot_rolls
      return nil if limit.nil? || limit <= 0
      current = guild.loot_rolls.open.count
      if current >= limit
        return error_response(
          I18n.t("discord.commands.errors.plan_limit",
                 feature: "loot rolls", limit: limit, plan: plan.name)
        )
      end
    when :events
      limit = plan.max_events
      return nil if limit.nil? || limit <= 0
      current = guild.discord_events.count
      if current >= limit
        return error_response(
          I18n.t("discord.commands.errors.plan_limit",
                 feature: "events", limit: limit, plan: plan.name)
        )
      end
    end

    nil
  end

  # =========================================================================
  # Response builders
  # =========================================================================

  # Immediate ephemeral text response (only visible to the invoking user).
  def ephemeral_response(message)
    { type: 4, data: { content: message, flags: EPHEMERAL_FLAG } }
  end

  alias_method :error_response, :ephemeral_response

  # Immediate public text response (visible to the channel).
  def public_response(message)
    { type: 4, data: { content: message } }
  end

  # Immediate response with embeds (ephemeral).
  # `embeds` can be a single embed hash or an array of embed hashes.
  def embed_response(embeds, components: [], ephemeral: true)
    embeds_array = embeds.is_a?(Array) ? embeds : [embeds]
    data = { embeds: embeds_array, components: Array(components) }
    data[:flags] = EPHEMERAL_FLAG if ephemeral
    { type: 4, data: data }
  end

  # Deferred response — tells Discord we will follow up within 15 minutes.
  # Type 5 = DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE (ephemeral by default)
  def deferred_response(ephemeral: true)
    data = {}
    data[:flags] = EPHEMERAL_FLAG if ephemeral
    { type: 5, data: data }
  end

  # =========================================================================
  # Follow-up messaging
  # =========================================================================

  # Post a follow-up message to an interaction webhook after deferral.
  def send_followup(interaction_token, content, components: [], ephemeral: true)
    return unless interaction_token.present?

    application_id = ENV["DISCORD_CLIENT_ID"]
    bot_token      = ENV["DISCORD_BOT_TOKEN"]

    payload = { content: content }
    payload[:flags]      = EPHEMERAL_FLAG if ephemeral
    payload[:components] = components     if components.any?

    RestClient.post(
      "#{DISCORD_API_BASE}/webhooks/#{application_id}/#{interaction_token}",
      payload.to_json,
      { "Authorization" => "Bot #{bot_token}", "Content-Type" => "application/json" }
    )
  rescue => e
    Rails.logger.error "[DiscordCommandHelpers] follow-up failed: #{e.class}: #{e.message}"
  end

  # =========================================================================
  # Subcommand extraction
  # =========================================================================

  # Return the subcommand name as a symbol from interaction data options.
  def subcommand_name(interaction)
    options = interaction.dig("data", "options") || []
    sub = options.find { |o| o["type"] == 1 }
    sub&.dig("name")&.to_sym
  end

  # Return the options hash for the matched subcommand, keyed by option name.
  def subcommand_options(interaction)
    options = interaction.dig("data", "options") || []
    sub = options.find { |o| o["type"] == 1 }
    return {} unless sub

    (sub["options"] || []).each_with_object({}) do |opt, h|
      h[opt["name"]] = opt["value"]
    end
  end

  # Return top-level command options (non-subcommand), keyed by name.
  def command_options(interaction)
    options = interaction.dig("data", "options") || []
    options.reject { |o| o["type"] == 1 }.each_with_object({}) do |opt, h|
      h[opt["name"]] = opt["value"]
    end
  end

  # =========================================================================
  # Date / time builder (universal across all commands)
  # =========================================================================

  DEFAULT_TIMEZONE = "Eastern Time (US & Canada)"

  # Build a UTC Time from user-friendly split options.
  #
  # Year is optional — defaults to the current year and auto-bumps to the
  # next year when the constructed time falls in the past (so users never
  # have to type the year for recurring near-future events).
  #
  # Timezone is resolved from the guild's default_timezone setting.
  # Fallback: Eastern Time (US & Canada).
  #
  # @param opts  [Hash]  must include :month, :day, :hour, :minute, :ampm.
  # @param guild [Guild] optional — used to read the guild's default timezone.
  # @return [Array(Time, nil)]   on success — [utc_time, nil]
  # @return [Array(nil, String)] on failure — [nil, error_message]
  def build_datetime_from_options(opts, guild: nil)
    month  = opts[:month].to_i
    day    = opts[:day].to_i
    hour   = opts[:hour].to_i
    minute = opts[:minute].to_i
    ampm   = opts[:ampm].to_s.upcase

    unless (1..12).cover?(month)
      return [nil, I18n.t("discord.commands.datetime.invalid_month")]
    end

    unless (1..12).cover?(hour) && (0..59).cover?(minute) && %w[AM PM].include?(ampm)
      return [nil, I18n.t("discord.commands.datetime.invalid_time")]
    end

    hour24 = ampm == "AM" ? (hour == 12 ? 0 : hour) : (hour == 12 ? 12 : hour + 12)

    tz_name = guild&.guild_discord_setting&.default_timezone.presence || DEFAULT_TIMEZONE
    tz      = ActiveSupport::TimeZone[tz_name] || ActiveSupport::TimeZone[DEFAULT_TIMEZONE]

    # Determine year — default to current; auto-bump if the date falls in the past
    year = opts[:year].to_i
    if year.zero?
      year = Time.current.year
      max_day = Date.new(year, month, -1).day
      unless (1..max_day).cover?(day)
        return [nil, I18n.t("discord.commands.datetime.invalid_day", max: max_day, month: Date::MONTHNAMES[month])]
      end

      utc_time = tz.local(year, month, day, hour24, minute).utc
      # If it's already past, try next year
      year += 1 if utc_time < Time.current
    else
      max_day = Date.new(year, month, -1).day
      unless (1..max_day).cover?(day)
        return [nil, I18n.t("discord.commands.datetime.invalid_day", max: max_day, month: Date::MONTHNAMES[month])]
      end
    end

    utc_time = tz.local(year, month, day, hour24, minute).utc

    if utc_time < Time.current
      return [nil, I18n.t("discord.commands.datetime.in_the_past")]
    end

    [utc_time, nil]
  rescue ArgumentError => e
    [nil, I18n.t("discord.commands.datetime.parse_error", detail: e.message)]
  end

  # =========================================================================
  # Private helpers
  # =========================================================================

  private

  def guild_owner?(guild, user)
    guild.owner_id == user.id
  end

  def guild_officer_by_role?(guild, user, guild_member)
    # High role enum values (moderator=1, admin=2, owner=3) are officer-level
    return true if guild_member.role.in?(%w[moderator admin owner])

    # Fallback: check Discord role-based permission flags
    role_id = guild_member.discord_role_id
    return false if role_id.blank?

    [1, 2, 3, 4].any? do |n|
      guild.public_send(:"permission_role_#{n}_id") == role_id &&
        (guild.public_send(:"role_#{n}_can_manage_applications?") ||
         guild.public_send(:"role_#{n}_can_manage_roles?"))
    end
  rescue NoMethodError
    false
  end
end
