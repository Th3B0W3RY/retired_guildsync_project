# frozen_string_literal: true

# Posts alliance-related Discord messages using each guild's own connected bot token
# (guild_discord_settings.bot_token) and the alliance channel IDs configured in guild settings.
# Failures are logged per-guild; they never raise to the caller (web request stays successful).
#
# If synchronous fan-out hits Discord rate limits, consider moving to a background job
# with exponential backoff (see DiscordService#update_message).
class AllianceDiscordBroadcastService
  ROLE_CATEGORIES = %w[dps tank healer ranged].freeze
  ROLE_EMOJIS = {
    "dps" => "⚔️",
    "tank" => "🛡️",
    "healer" => "➕",
    "ranged" => "🏹"
  }.freeze

  ATTENDANCE_STATUSES = %w[on_time late absent].freeze

  # Discord requires allowed_mentions so @everyone actually pings.
  EVERYONE_ALLOWED_MENTIONS = { parse: [ "everyone" ] }.freeze

  class << self
    def routes
      Rails.application.routes.url_helpers
    end

    def notify_invite_created(invite)
      guild = invite.guild
      setting = guild.guild_discord_setting
      return unless setting
      token = bot_token_for(setting)
      return if token.blank?

      channel_id = setting.alliance_channel_for_invite_notification
      return if channel_id.blank?

      url = routes.alliance_url(invite.alliance, **app_url_options)
      embed = {
        title:       I18n.t("alliances.discord.invite_embed.title", alliance_name: invite.alliance.name),
        description: I18n.t("alliances.discord.invite_embed.body", inviter: invite.invited_by_user.username),
        url:         url,
        color:       0x5865F2,
        footer:      { text: "GuildSync" }
      }

      post_safe(token, channel_id, embed: embed, content: "")
    end

    def notify_join_request_created(join_request)
      alliance = join_request.alliance
      broadcast_plain_to_member_guilds(
        alliance,
        channel_resolver: ->(s) { s.alliance_channel_for_invite_notification },
        embed:            {
          title:       I18n.t("alliances.discord.join_request_embed.title", guild_name: join_request.requesting_guild.name),
          description: I18n.t(
            "alliances.discord.join_request_embed.body",
            guild_name:    join_request.requesting_guild.name,
            alliance_name: alliance.name
          ),
          url:         routes.alliance_url(alliance, **app_url_options),
          color:       0xF0B132,
          footer:      { text: "GuildSync" }
        }
      )
    end

    def broadcast_alliance_event_created(alliance, event)
      broadcast_to_member_guilds(
        alliance,
        channel_resolver: ->(s) { s.alliance_events_channel_id.presence },
        event:            event
      )
    end

    def broadcast_alliance_event_updated(event)
      update_event_messages(event)
    end

    def broadcast_alliance_event_deleted(event)
      event.alliance_event_discord_messages.includes(guild: :guild_discord_setting).find_each do |message_link|
        setting = message_link.guild.guild_discord_setting
        token = bot_token_for(setting)
        if token.present? && message_link.discord_scheduled_event_id.present?
          begin
            DiscordService.new(bot_token: token).delete_scheduled_event!(
              guild: message_link.guild,
              scheduled_event_id: message_link.discord_scheduled_event_id
            )
          rescue StandardError => e
            Rails.logger.warn "[AllianceDiscordBroadcastService] Failed deleting Discord scheduled event=#{message_link.discord_scheduled_event_id} event=#{event.id}: #{e.class}: #{e.message}"
          end
        end

        next if token.blank?

        begin
          DiscordService.new(bot_token: token).delete_message(message_link.channel_id, message_link.discord_message_id)
        rescue StandardError => e
          Rails.logger.warn "[AllianceDiscordBroadcastService] Failed deleting alliance event message=#{message_link.discord_message_id} for event=#{event.id}: #{e.class}: #{e.message}"
        end
      end

      event.alliance_event_discord_messages.destroy_all
    end

    def broadcast_alliance_poll_created(alliance, poll)
      poll_service = DiscordAlliancePollService.new(poll)
      alliance.alliance_guilds.where(status: :active).includes(guild: :guild_discord_setting).find_each do |ag|
        guild = ag.guild
        setting = guild.guild_discord_setting
        next unless setting

        token = bot_token_for(setting)
        next if token.blank?

        channel_id = setting.alliance_polls_channel_id.presence
        next if channel_id.blank?

        begin
          poll_content = "@everyone\n\n**New Alliance Poll** — vote below."
          response = DiscordService.new(bot_token: token).send_message(
            channel_id,
            poll_content,
            embed: poll_service.build_embed(guild: guild),
            components: poll_service.build_buttons,
            allowed_mentions: EVERYONE_ALLOWED_MENTIONS
          )
          message_id = response&.dig("id")
          next if message_id.blank?

          link = poll.alliance_poll_discord_messages.find_or_initialize_by(guild: guild)
          link.channel_id = channel_id
          link.discord_message_id = message_id
          link.posted_at = Time.current
          link.save!
        rescue StandardError => e
          Rails.logger.warn "[AllianceDiscordBroadcastService] Alliance poll Discord post failed (guild=#{guild.id}): #{e.class}: #{e.message}"
        end
      end
    end

    def broadcast_alliance_loot_roll_created(alliance, loot_roll)
      loot_service = DiscordAllianceLootRollService.new(loot_roll)
      alliance.alliance_guilds.where(status: :active).includes(guild: :guild_discord_setting).find_each do |ag|
        guild = ag.guild
        setting = guild.guild_discord_setting
        next unless setting

        token = bot_token_for(setting)
        next if token.blank?

        channel_id = setting.alliance_loot_rolls_channel_id.presence
        next if channel_id.blank?

        begin
          content = "@everyone\n\n**New Alliance Loot Roll!** Click the button below to roll (link your Discord in GuildSync if you have not)."
          response = DiscordService.new(bot_token: token).send_message(
            channel_id,
            content,
            embed: loot_service.build_embed(guild: guild),
            components: loot_service.build_buttons,
            allowed_mentions: EVERYONE_ALLOWED_MENTIONS
          )
          message_id = response&.dig("id")
          next if message_id.blank?

          link = loot_roll.alliance_loot_roll_discord_messages.find_or_initialize_by(guild: guild)
          link.channel_id = channel_id
          link.discord_message_id = message_id
          link.posted_at = Time.current
          link.save!
        rescue StandardError => e
          Rails.logger.warn "[AllianceDiscordBroadcastService] Alliance loot roll Discord post failed (guild=#{guild.id}): #{e.class}: #{e.message}"
        end
      end
    end

    # Optional: announce when a guild accepts an invite (fan-out to all member guilds).
    def notify_guild_joined_alliance(alliance, joined_guild)
      broadcast_plain_to_member_guilds(
        alliance,
        channel_resolver: ->(s) { s.alliance_channel_for_invite_notification },
        embed:            {
          title:       I18n.t("alliances.discord.member_joined_embed.title", guild_name: joined_guild.name),
          description: I18n.t("alliances.discord.member_joined_embed.body", alliance_name: alliance.name),
          url:         routes.alliance_url(alliance, **app_url_options),
          color:       0x57F287,
          footer:      { text: "GuildSync" }
        }
      )
    end

    private

    def app_url_options
      opts = Rails.application.config.action_mailer.default_url_options&.dup || {}
      opts[:host] ||= ENV.fetch("APP_HOST", "localhost")
      opts[:protocol] ||= (Rails.env.production? ? "https" : "http")
      opts[:port] ||= ENV["APP_PORT"].presence
      opts.compact
    end

    def broadcast_to_member_guilds(alliance, channel_resolver:, event:)
      alliance.alliance_guilds.where(status: :active).includes(guild: :guild_discord_setting).find_each do |ag|
        guild = ag.guild
        setting = guild.guild_discord_setting
        unless setting
          Rails.logger.info "[AllianceDiscordBroadcastService] Skipping guild=#{guild.id}: missing guild_discord_setting"
          next
        end

        token = bot_token_for(setting)
        if token.blank?
          Rails.logger.info "[AllianceDiscordBroadcastService] Skipping guild=#{guild.id}: missing bot token"
          next
        end

        channel_id = channel_resolver.call(setting)
        if channel_id.blank?
          Rails.logger.info "[AllianceDiscordBroadcastService] Skipping guild=#{guild.id}: missing alliance_events_channel_id"
          next
        end

        post_event_message_for_guild(event, guild, token, channel_id)
      end
    end

    def broadcast_plain_to_member_guilds(alliance, channel_resolver:, embed:, components: nil)
      alliance.alliance_guilds.where(status: :active).includes(guild: :guild_discord_setting).find_each do |ag|
        guild = ag.guild
        setting = guild.guild_discord_setting
        next unless setting
        token = bot_token_for(setting)
        next if token.blank?

        channel_id = channel_resolver.call(setting)
        next if channel_id.blank?

        post_safe(token, channel_id, embed: embed, content: "", components: components)
      end
    end

    def bot_token_for(setting)
      setting.bot_token.presence || ENV["DISCORD_BOT_TOKEN"].presence
    end

    def post_event_message_for_guild(event, guild, token, channel_id)
      body = "**New Alliance Event Created!** Click buttons below to sign up by role:"
      content = "@everyone\n\n#{body}"

      service = DiscordService.new(bot_token: token)
      response = service.send_message(
        channel_id,
        content,
        embed: build_event_embed(event, target_guild: guild),
        components: role_buttons_for(event),
        allowed_mentions: EVERYONE_ALLOWED_MENTIONS
      )

      message_id = response&.dig("id")
      return if message_id.blank?

      link = event.alliance_event_discord_messages.find_or_initialize_by(guild: guild)
      link.channel_id = channel_id
      link.discord_message_id = message_id
      link.posted_at = Time.current

      begin
        se_id = service.create_scheduled_event!(
          guild: guild,
          channel_id: channel_id,
          name: event.title.to_s.strip.truncate(100),
          description: discord_scheduled_event_description(event),
          start_time: event.scheduled_at,
          event_type: event.event_type,
          duration_minutes: event.duration
        )
        link.discord_scheduled_event_id = se_id if se_id.present?
      rescue StandardError => e
        Rails.logger.warn "[AllianceDiscordBroadcastService] Scheduled event creation skipped guild=#{guild.id} event=#{event.id}: #{e.class}: #{e.message}"
      end

      link.save!
    rescue StandardError => e
      Rails.logger.warn "[AllianceDiscordBroadcastService] Discord post failed (guild=#{guild.id}, channel=#{channel_id}): #{e.class}: #{e.message}"
      nil
    end

    def post_safe(bot_token, channel_id, embed:, content:, components: nil)
      DiscordService.new(bot_token: bot_token).send_message(channel_id, content, embed: embed, components: components)
    rescue StandardError => e
      Rails.logger.warn "[AllianceDiscordBroadcastService] Discord post failed (channel=#{channel_id}): #{e.class}: #{e.message}"
      nil
    end

    def update_event_messages(event)
      signup_content = "@everyone\n\n**Alliance Event Signups** - Click buttons below to sign up by role:"
      event.alliance_event_discord_messages.includes(guild: :guild_discord_setting).find_each do |message_link|
        setting = message_link.guild.guild_discord_setting
        token = bot_token_for(setting)
        next if token.blank?

        begin
          DiscordService.new(bot_token: token).update_message(
            message_link.channel_id,
            message_link.discord_message_id,
            signup_content,
            embed: build_event_embed(event, target_guild: message_link.guild),
            components: role_buttons_for(event),
            allowed_mentions: EVERYONE_ALLOWED_MENTIONS
          )
        rescue StandardError => e
          Rails.logger.warn "[AllianceDiscordBroadcastService] Discord update failed (message=#{message_link.discord_message_id}): #{e.class}: #{e.message}"
        end

        next if message_link.discord_scheduled_event_id.blank?

        begin
          DiscordService.new(bot_token: token).patch_scheduled_event!(
            guild: message_link.guild,
            scheduled_event_id: message_link.discord_scheduled_event_id,
            name: event.title.to_s.strip.truncate(100),
            description: discord_scheduled_event_description(event),
            start_time: event.scheduled_at,
            end_time: alliance_event_scheduled_end_time(event)
          )
        rescue StandardError => e
          Rails.logger.warn "[AllianceDiscordBroadcastService] Discord scheduled event patch failed guild=#{message_link.guild_id} event=#{event.id}: #{e.class}: #{e.message}"
        end
      end
    end

    def build_event_embed(event, target_guild:)
      fields = []

      row1_fields = []
      squad_leader_name = event.squad_leader.presence || event.created_by&.name_for_discord_embed || "Unknown"
      row1_fields << {
        name: "**👤 Squad Leader**",
        value: "**#{squad_leader_name}**",
        inline: true
      }
      if event.location.present?
        row1_fields << {
          name: "**📍 Location**",
          value: "**#{event.location}**",
          inline: true
        }
      end
      row1_fields << {
        name: "**📅 Type**",
        value: "**#{AllianceEvent.event_type_label(event.event_type)}**",
        inline: true
      }
      row1_fields << {
        name: "**👥 Total**",
        value: "**#{signed_up_total(event)}**",
        inline: true
      }
      if event.max_participants.present?
        row1_fields << {
          name: "**👥 Max**",
          value: "**#{event.max_participants}**",
          inline: true
        }
      end
      fields.concat(row1_fields)

      ROLE_CATEGORIES.each do |role|
        role_signups = event.alliance_event_discord_signups.where(role: role, status: :on_time)
        display_names = role_signups.map { |signup| signup.discord_display_name.presence || signup.discord_username }
        fields << {
          name: "**#{ROLE_EMOJIS.fetch(role)} #{role.upcase} (#{role_signups.count})**",
          value: display_names.any? ? format_usernames_in_columns(display_names) : "```None```",
          inline: true
        }
      end

      late_users = event.alliance_event_discord_signups.where(status: :late).map { |s| s.discord_display_name.presence || s.discord_username }
      absent_users = event.alliance_event_discord_signups.where(status: :absent).map { |s| s.discord_display_name.presence || s.discord_username }

      fields << { name: "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", value: "**STATUS**", inline: false }
      fields << { name: "**⏰ Late**", value: late_users.any? ? format_usernames_in_columns(late_users) : "**None**", inline: true }
      fields << { name: "**❌ Absent**", value: absent_users.any? ? format_usernames_in_columns(absent_users) : "**None**", inline: true }

      description_text = event.description.presence || "Join us for this alliance event!"
      server = target_guild.discord_server_display_name
      {
        title: "🎯 #{event.title}",
        description: "**⏰ Scheduled:** <t:#{event.scheduled_at.to_i}:F>\n\n#{description_text}",
        url: routes.alliance_alliance_event_url(event.alliance, event, **app_url_options),
        color: 0x57F287,
        fields: fields,
        timestamp: event.scheduled_at.iso8601,
        footer: { text: "GuildSync Alliance Event • #{server} • Click buttons below to sign up" }
      }
    end

    def role_buttons_for(event)
      event_id = event.id
      categories = event.role_categories_for_discord
      return [] if categories.empty?

      categories.each_slice(5).map do |role_batch|
        {
          type: 1,
          components: role_batch.map do |role|
            {
              type: 2,
              style: 1,
              label: "#{ROLE_EMOJIS.fetch(role)} #{role.upcase}",
              custom_id: "alliance_event_signup_#{event_id}_#{role}"
            }
          end
        }
      end
    end

    def discord_scheduled_event_description(event)
      text = event.description.to_s.strip.presence || "Join us for this alliance event!"
      text.length > 1000 ? text[0..996] + "..." : text
    end

    def alliance_event_scheduled_end_time(event)
      if event.duration.present? && event.duration.to_i.positive?
        event.scheduled_at + event.duration.to_i.minutes
      else
        event.scheduled_at + 1.hour
      end
    end

    def attendance_buttons_for(event_id, role, discord_user_id)
      [ {
        type: 1,
        components: ATTENDANCE_STATUSES.map do |status|
          {
            type: 2,
            style: status == "absent" ? 4 : (status == "late" ? 2 : 1),
            label: attendance_label_for(status),
            custom_id: "alliance_event_status_#{event_id}_#{role}_#{status}_#{discord_user_id}"
          }
        end + [ {
          type: 2,
          style: 4,
          label: "Remove",
          custom_id: "alliance_event_status_#{event_id}_#{role}_remove_#{discord_user_id}"
        } ]
      } ]
    end

    def apply_status_selection(event_id:, role:, status:, discord_user_id:, discord_username:, discord_display_name: nil)
      event = AllianceEvent.find_by(id: event_id)
      return { ok: false, error: :event_not_found } unless event
      return { ok: false, error: :invalid_status } unless ATTENDANCE_STATUSES.include?(status) || status == "remove"
      allowed_roles = event.role_categories_for_discord
      return { ok: false, error: :invalid_role } unless allowed_roles.include?(role)

      handler = UnregisteredInteractionHandler.new(discord_user_id: discord_user_id, discord_username: discord_username)
      user = handler.resolve_user

      if user
        active_member = event.alliance.alliance_members.where(user_id: user.id, status: :active).exists?
        return { ok: false, error: :not_alliance_member } unless active_member
      end

      if status == "remove"
        event.alliance_event_discord_signups.find_by(discord_user_id: discord_user_id.to_s)&.destroy
      else
        signup = event.alliance_event_discord_signups.find_or_initialize_by(discord_user_id: discord_user_id.to_s)
        signup.role = role
        signup.status = status
        signup.discord_username = discord_username
        signup.discord_display_name = discord_display_name.presence || discord_username
        signup.save!
      end

      handler.send_onboarding_dm_if_needed(context_type: "Alliance", context_id: event.alliance_id) unless user

      update_event_messages(event)
      { ok: true, event: event }
    rescue ActiveRecord::RecordInvalid => e
      { ok: false, error: :save_failed, message: e.message }
    end

    def signed_up_total(event)
      event.alliance_event_discord_signups.where(status: %i[on_time late]).count
    end

    def attendance_label_for(status)
      case status
      when "on_time" then "✅ On Time"
      when "late" then "⏰ Late"
      when "absent" then "❌ Absent"
      else status.humanize
      end
    end

    def format_usernames_in_columns(usernames, max_per_column = 5)
      return "```None```" if usernames.empty?

      columns = usernames.each_slice(max_per_column).to_a
      return "```#{columns.first.join("\n")}```" if columns.length == 1

      columns.map { |col| "```#{col.join("\n")}```" }.join(" ")
    end

    public :attendance_buttons_for, :apply_status_selection
  end
end
