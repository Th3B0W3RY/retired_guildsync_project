# frozen_string_literal: true

# Per-guild Discord messages for alliance loot rolls; one "Roll" button resolves to GuildSync user + entry.
class DiscordAllianceLootRollService
  def initialize(alliance_loot_roll)
    @roll = alliance_loot_roll
  end

  def self.update_all_linked_messages(loot_roll)
    new(loot_roll).update_all_linked_messages
  end

  def self.delete_all_linked_messages(loot_roll)
    new(loot_roll).delete_all_linked_messages
  end

  def build_embed(guild: nil)
    entries = @roll.alliance_loot_roll_entries.order(roll_value: :desc)
    total_entries = entries.count
    highest = @roll.highest_roll

    description = @roll.description.present? ? @roll.description : "Roll for loot!"
    description += "\n\n**🎲 Roll Range:** #{@roll.min_roll} - #{@roll.max_roll}"

    if @roll.deadline_at.present?
      ts = @roll.deadline_at.to_i
      description += "\n**⏰ Deadline:** <t:#{ts}:R> (<t:#{ts}:F>)"
    end

    fields = []

    cache = {} if guild.present?
    if total_entries.positive?
      results_text = entries.limit(15).map do |entry|
        roll_display = entry.roll_value.to_s
        name_display =
          if @roll.anonymous?
            "Anonymous"
          elsif entry.user.nil?
            entry.display_name.presence || entry.discord_username.presence || "Discord User"
          elsif guild.present?
            DiscordGuildMemberLabel.for_user_in_guild(user: entry.user, guild: guild, cache: cache)
          else
            entry.display_name
          end
        is_highest = entry.roll_value == highest && highest.present?
        if is_highest && @roll.open?
          "🏆 **#{name_display}** - **#{roll_display}**"
        else
          "#{name_display} - #{roll_display}"
        end
      end.join("\n")

      results_text += "\n... and #{total_entries - 15} more" if total_entries > 15

      fields << { name: "🎲 Rolls (#{total_entries})", value: results_text, inline: false }
    else
      fields << { name: "🎲 Rolls", value: "No rolls yet. Be the first to roll!", inline: false }
    end

    if @roll.closed? && @roll.winner_entry.present?
      winner = @roll.winner_entry
      wname =
        if @roll.anonymous?
          "Anonymous"
        elsif winner.user.nil?
          winner.display_name.presence || winner.discord_username.presence || "Discord User"
        elsif guild.present?
          DiscordGuildMemberLabel.for_user_in_guild(user: winner.user, guild: guild, cache: cache)
        else
          winner.display_name
        end
      fields << {
        name: "🏆 Winner",
        value: "**#{wname}** with a roll of **#{winner.roll_value}**!",
        inline: false
      }
    end

    status_text =
      if @roll.closed?
        "🔴 Closed"
      elsif @roll.currently_open?
        "🟢 Open"
      else
        "🔴 Closed"
      end

    fields << { name: "Status", value: status_text, inline: true }
    fields << { name: "Total Rolls", value: total_entries.to_s, inline: true }

    embed_color =
      if @roll.closed?
        0xFF0000
      elsif @roll.currently_open?
        0x00FF00
      else
        0xFF0000
      end

    server_suffix = guild ? " • #{guild.discord_server_display_name}" : ""

    {
      title: "🎲 #{@roll.title}",
      url: roll_url,
      description: description,
      color: embed_color,
      fields: fields,
      timestamp: @roll.deadline_at&.iso8601,
      footer: { text: "GuildSync Alliance Loot Roll#{server_suffix} • Click the button below to roll" }
    }
  end

  def build_buttons
    return [] unless @roll.currently_open?

    [
      {
        type: 1,
        components: [
          {
            type: 2,
            style: 1,
            label: "🎲 Roll",
            custom_id: "alliance_loot_roll_#{@roll.id}_roll"
          }
        ]
      }
    ]
  end

  def update_all_linked_messages
    @roll.reload
    components = build_buttons

    @roll.alliance_loot_roll_discord_messages.includes(guild: :guild_discord_setting).find_each do |link|
      embed = build_embed(guild: link.guild)
      setting = link.guild.guild_discord_setting
      token = bot_token_for(setting)
      next if token.blank?

      DiscordService.new(bot_token: token).update_message(
        link.channel_id,
        link.discord_message_id,
        nil,
        embed: embed,
        components: components
      )
    rescue StandardError => e
      Rails.logger.warn "[DiscordAllianceLootRollService] update failed roll=#{@roll.id} guild=#{link.guild_id}: #{e.class}: #{e.message}"
    end
  end

  def delete_all_linked_messages
    @roll.alliance_loot_roll_discord_messages.includes(guild: :guild_discord_setting).find_each do |link|
      setting = link.guild.guild_discord_setting
      token = bot_token_for(setting)
      next if token.blank?

      DiscordService.new(bot_token: token).delete_message(link.channel_id, link.discord_message_id)
    rescue StandardError => e
      Rails.logger.warn "[DiscordAllianceLootRollService] delete failed roll=#{@roll.id} guild=#{link.guild_id}: #{e.class}: #{e.message}"
    end
  end

  private

  def bot_token_for(setting)
    setting&.bot_token.presence || ENV["DISCORD_BOT_TOKEN"].presence
  end

  def roll_url
    Rails.application.routes.url_helpers.alliance_alliance_loot_roll_url(
      @roll.alliance,
      @roll,
      **app_url_options
    )
  end

  def app_url_options
    opts = Rails.application.config.action_mailer.default_url_options&.dup || {}
    opts[:host] ||= ENV.fetch("APP_HOST", "localhost")
    opts[:protocol] ||= (Rails.env.production? ? "https" : "http")
    opts[:port] ||= ENV["APP_PORT"].presence
    opts.compact
  end
end
