require "rest-client"
require "json"

class DiscordLootRollService
  DISCORD_API_BASE = "https://discord.com/api/v10"

  def initialize(loot_roll)
    @loot_roll = loot_roll
    @guild = loot_roll.guild
    @discord_setting = @guild.guild_discord_setting
    @bot_token = @discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
  end

  def post_loot_roll
    unless @discord_setting&.connected?
      raise "Discord not connected for this guild"
    end

    channel_id = @loot_roll.discord_channel_id || @discord_setting.loot_rolls_channel_id
    unless channel_id.present?
      raise "Loot Rolls channel not configured. Please configure it in guild settings."
    end

    embed = build_embed
    components = build_buttons

    # Build role mentions if any are selected
    content = ""
    if @loot_roll.allowed_role_ids.present? && @loot_roll.allowed_role_ids.any?
      discord_guild_id = @discord_setting&.discord_guild_id
      role_names_by_id = @guild.discord_role_syncs.where(role_id: @loot_roll.allowed_role_ids).pluck(:role_id, :role_name).to_h

      content = @loot_roll.allowed_role_ids.uniq.map do |id|
        role_name = role_names_by_id[id.to_s]
        if (discord_guild_id.present? && id.to_s == discord_guild_id.to_s) || role_name&.downcase == "@everyone"
          "@everyone"
        else
          "<@&#{id}>"
        end
      end.join(" ")
    end

    response = RestClient.post(
      "#{DISCORD_API_BASE}/channels/#{channel_id}/messages",
      {
        content: content.presence,
        embeds: [embed],
        components: components
      }.compact.to_json,
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )

    message_data = JSON.parse(response.body)
    @loot_roll.update!(
      discord_message_id: message_data["id"],
      discord_channel_id: channel_id
    )

    message_data
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "Failed to post loot roll to Discord: #{e.response.code} - #{e.response.body}"
    raise "Failed to post loot roll to Discord: #{e.response.body}"
  end

  def update_loot_roll_message
    return unless @loot_roll.discord_message_id.present? && @loot_roll.discord_channel_id.present?

    embed = build_embed
    components = build_buttons

    RestClient.patch(
      "#{DISCORD_API_BASE}/channels/#{@loot_roll.discord_channel_id}/messages/#{@loot_roll.discord_message_id}",
      {
        embeds: [embed],
        components: components
      }.to_json,
      {
        "Authorization" => "Bot #{@bot_token}",
        "Content-Type" => "application/json"
      }
    )
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "Failed to update loot roll message on Discord: #{e.response.code} - #{e.response.body}"
  end

  private

  def guild_loot_entry_label(entry, cache)
    return "Anonymous" if @loot_roll.anonymous?

    DiscordGuildMemberLabel.for_discord_user_in_guild(
      discord_user_id: entry.discord_user_id,
      guild: @guild,
      cache: cache,
      fallback_display: entry.display_name
    )
  end

  def build_embed
    entries = @loot_roll.loot_roll_entries.active.ordered_by_roll
    total_entries = entries.count
    highest_roll = @loot_roll.highest_roll

    # Build description
    description = @loot_roll.description.present? ? @loot_roll.description : "Roll for loot!"
    description += "\n\n**🎲 Roll Range:** #{@loot_roll.min_roll} - #{@loot_roll.max_roll}"

    if @loot_roll.deadline_at.present?
      deadline_timestamp = @loot_roll.deadline_at.to_i
      description += "\n**⏰ Deadline:** <t:#{deadline_timestamp}:R> (<t:#{deadline_timestamp}:F>)"
    end

    # Build fields
    fields = []
    label_cache = {}

    # Results field
    if total_entries > 0
      results_text = entries.limit(15).map.with_index do |entry, index|
        roll_display = entry.roll_value.to_s
        
        # Highlight if this is the highest roll
        is_highest = entry.roll_value == highest_roll
        name_display = guild_loot_entry_label(entry, label_cache)

        # Mark tied entries
        is_tied = @loot_roll.has_tie? && entry.roll_value == highest_roll

        if is_highest && !is_tied
          "🏆 **#{name_display}** - **#{roll_display}**"
        elsif is_tied
          "⚠️ **#{name_display}** - **#{roll_display}** (TIED)"
        else
          "#{name_display} - #{roll_display}"
        end
      end.join("\n")

      if total_entries > 15
        results_text += "\n... and #{total_entries - 15} more"
      end

      fields << {
        name: "🎲 Rolls (#{total_entries})",
        value: results_text,
        inline: false
      }
    else
      fields << {
        name: "🎲 Rolls",
        value: "No rolls yet. Be the first to roll!",
        inline: false
      }
    end

    # Tie-breaker field (if there's a tie)
    if @loot_roll.has_tie? && @loot_roll.currently_open?
      tied_entries = entries.where(roll_value: highest_roll)
      tied_names = tied_entries.map { |e| guild_loot_entry_label(e, label_cache) }.join(", ")

      fields << {
        name: "⚠️ TIE DETECTED!",
        value: "**#{tied_names}** are tied at **#{highest_roll}**!\n\nTied users must click the **Reroll Tie-Breaker** button below.",
        inline: false
      }
    end

    # Winner field (if closed)
    if @loot_roll.closed? && @loot_roll.winner_entry.present?
      winner = @loot_roll.winner_entry
      wlabel = guild_loot_entry_label(winner, label_cache)
      fields << {
        name: "🏆 Winner",
        value: "**#{wlabel}** with a roll of **#{winner.roll_value}**!",
        inline: false
      }
    end

    # Status field
    if @loot_roll.has_tie?
      status_text = "⚠️ Tie-Breaker Round #{@loot_roll.current_tiebreaker_round}"
    elsif @loot_roll.currently_open?
      status_text = "🟢 Open"
    else
      status_text = "🔴 Closed"
    end

    fields << {
      name: "Status",
      value: status_text,
      inline: true
    }

    fields << {
      name: "Total Rolls",
      value: total_entries.to_s,
      inline: true
    }

    # Determine embed color
    if @loot_roll.has_tie?
      embed_color = 0xFFA500 # Orange for tie
    elsif @loot_roll.currently_open?
      embed_color = 0x00FF00 # Green for open
    else
      embed_color = 0xFF0000 # Red for closed
    end

    server = @guild.discord_server_display_name
    # Determine footer text
    if @loot_roll.has_tie?
      footer_text = "GuildSync Loot Roll • #{server} • Tied users: click Reroll Tie-Breaker"
    else
      footer_text = "GuildSync Loot Roll • #{server} • Click the button below to roll"
    end

    {
      title: "🎲 #{@loot_roll.title}",
      description: description,
      color: embed_color,
      fields: fields,
      timestamp: @loot_roll.deadline_at&.iso8601,
      footer: {
        text: footer_text
      }
    }
  end

  def build_buttons
    return [] unless @loot_roll.currently_open?

    # If there's a tie, only show tiebreaker button
    if @loot_roll.has_tie?
      return [
        {
          type: 1, # ACTION_ROW
          components: [
            {
              type: 2, # BUTTON
              style: 4, # DANGER (red) to stand out
              label: "🎲 Reroll Tie-Breaker",
              custom_id: "loot_roll_#{@loot_roll.id}_tiebreaker"
            }
          ]
        }
      ]
    end

    # Normal roll button
    [
      {
        type: 1, # ACTION_ROW
        components: [
          {
            type: 2, # BUTTON
            style: 1, # PRIMARY (blurple)
            label: "🎲 Roll",
            custom_id: "loot_roll_#{@loot_roll.id}_roll"
          }
        ]
      }
    ]
  end
end
