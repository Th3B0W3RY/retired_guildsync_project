# frozen_string_literal: true

# Resolves how a user should appear in Discord embeds for a specific Discord server:
# server nickname → Discord global display name → login username (last resort).
class DiscordGuildMemberLabel
  class << self
    # Raw Discord API member object (GET /guilds/:id/members/:uid) or interaction "member" payload.
    def from_member_json(member)
      return nil if member.blank?

      member = member.to_unsafe_h if member.respond_to?(:to_unsafe_h)
      member = member.stringify_keys if member.respond_to?(:stringify_keys)

      nick = member["nick"].presence
      return nick if nick.present?

      user_obj = member["user"]
      from_user_json(user_obj)
    end

    # Interaction "user" object only (no server nickname in payload).
    def from_user_json(user_obj)
      return nil if user_obj.blank?

      user_obj = user_obj.to_unsafe_h if user_obj.respond_to?(:to_unsafe_h)
      user_obj = user_obj.stringify_keys if user_obj.respond_to?(:stringify_keys)
      return nil unless user_obj.is_a?(Hash)

      global = user_obj["global_name"].presence
      return global if global.present?

      username_with_optional_discriminator(user_obj)
    end

    def username_with_optional_discriminator(user_obj)
      u = user_obj["username"].to_s
      return nil if u.blank?

      disc = user_obj["discriminator"]
      (disc.present? && disc != "0") ? "#{u}##{disc}" : u
    end

    # GuildSync user + member guild (whose Discord embed we're rendering).
    def for_user_in_guild(user:, guild:, cache: nil)
      return fallback_label(user) unless user && guild.present?

      uid = user.discord_user_id.presence || user.user_discord_connection&.discord_user_id
      return fallback_label(user) if uid.blank?

      cache_key = uid.to_s
      if cache&.key?(cache_key)
        return cache[cache_key].presence || fallback_label(user)
      end

      label = fetch_label_for_discord_ids(discord_user_id: uid, guild: guild)
      label = label.presence || fallback_label(user)
      cache[cache_key] = label if cache
      label
    end

    # Loot roll lines: Discord user id string, optional linked User, stored fallback (legacy display_name).
    def for_discord_user_in_guild(discord_user_id:, guild:, cache: nil, fallback_display: nil)
      did = discord_user_id.to_s
      return fallback_display.presence || "Player" if did.blank? || guild.blank?

      cache_key = did
      if cache&.key?(cache_key)
        return cache[cache_key].presence || fallback_display.presence || "Player"
      end

      user = User.find_by(discord_user_id: did)
      user ||= UserDiscordConnection.find_by(discord_user_id: did)&.user
      if user
        label = for_user_in_guild(user: user, guild: guild, cache: cache)
        return label
      end

      label = fetch_label_for_discord_ids(discord_user_id: did, guild: guild)
      label = label.presence || fallback_display.presence || "Player"
      cache[cache_key] = label if cache
      label
    end

    def fallback_label(user)
      return "Member" unless user

      user.discord_global_name.presence ||
        user.username.presence ||
        (user.discord_username.present? ? user.clean_discord_username(user.discord_username) : nil) ||
        "Member"
    end

    def guild_from_discord_snowflake(snowflake)
      sid = snowflake.to_s
      return nil if sid.blank?

      Guild.find_by(discord_id: sid) ||
        Guild.joins(:guild_discord_setting).find_by(guild_discord_settings: { discord_guild_id: sid })
    end

    private

    def fetch_label_for_discord_ids(discord_user_id:, guild:)
      setting = guild.guild_discord_setting
      snowflake = guild.discord_id.presence || setting&.discord_guild_id
      token = setting&.bot_token.presence || ENV["DISCORD_BOT_TOKEN"].presence
      return nil if snowflake.blank? || token.blank?

      svc = DiscordService.new(bot_token: token)
      member = svc.get_guild_member(snowflake, discord_user_id)
      from_member_json(member) if member
    rescue StandardError => e
      Rails.logger.warn "[DiscordGuildMemberLabel] member fetch failed guild=#{guild.id} uid=#{discord_user_id}: #{e.message}"
      nil
    end
  end
end
