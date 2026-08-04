# frozen_string_literal: true

require "rest-client"

# Handles the /loot slash command and all its subcommands.
#
# Subcommands:
#   /loot create  item_name:<str> [min:<int>] [max:<int>] [deadline_minutes:<int>]
#   /loot list    — list open loot rolls (ephemeral)
#   /loot view    loot_id:<int> — view a specific loot roll (ephemeral)
#   /loot close   loot_id:<int> — close and determine winner (officer+)
class DiscordLootCommandService
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
    when :close  then handle_close
    else ephemeral_response(I18n.t("discord.commands.errors.unknown_subcommand"))
    end
  end

  private

  def handle_create
    guard = require_officer!(@guild, @user, @guild_member)
    return guard if guard

    limit_guard = enforce_plan_limit!(@guild, :loot_rolls)
    return limit_guard if limit_guard

    unless @guild.guild_discord_setting&.loot_rolls_channel_configured?
      return ephemeral_response(I18n.t("discord.commands.loot.no_channel"))
    end

    opts             = subcommand_options(@interaction)
    item_name        = opts["item_name"].to_s.strip
    min_roll         = [opts["min"].to_i, 1].max
    max_roll         = opts["max"].to_i > 0 ? opts["max"].to_i : 100
    deadline_minutes = opts["deadline_minutes"].to_i > 0 ? opts["deadline_minutes"].to_i : nil

    if item_name.blank?
      return ephemeral_response(I18n.t("discord.commands.loot.missing_item"))
    end

    if max_roll <= min_roll
      return ephemeral_response(I18n.t("discord.commands.loot.invalid_range"))
    end

    interaction_token = @interaction_token
    guild             = @guild
    user              = @user

    deadline_at = deadline_minutes ? deadline_minutes.minutes.from_now : nil

    DiscordCommandJob.perform_later(
      "DiscordLootCommandService",
      "process_create",
      interaction_token,
      guild.id,
      user.id,
      {
        item_name: item_name,
        min_roll: min_roll,
        max_roll: max_roll,
        deadline_at: deadline_at&.to_s
      }
    )

    deferred_response(ephemeral: true)
  end

  # Called by DiscordCommandJob
  def process_create(opts)
    loot_roll = @guild.loot_rolls.create!(
      title:       opts[:item_name],
      min_roll:    opts[:min_roll],
      max_roll:    opts[:max_roll],
      deadline_at: opts[:deadline_at] ? Time.zone.parse(opts[:deadline_at]) : nil,
      status:      :open,
      creator:     @user
    )

    service = DiscordLootRollService.new(loot_roll)
    service.post_loot_roll

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "loot_roll_created",
      description: "Created loot roll via Discord: \"#{opts[:item_name]}\"",
      subject:     loot_roll,
      title:       opts[:item_name]
    )

    send_followup(
      @interaction_token,
      I18n.t("discord.commands.loot.created", item: opts[:item_name]),
      ephemeral: true
    )
  end

  def handle_list
    rolls = @guild.loot_rolls.open.ordered.limit(10)

    if rolls.empty?
      return ephemeral_response(I18n.t("discord.commands.loot.none_active"))
    end

    lines = rolls.map do |lr|
      deadline_str = lr.deadline_at ? "<t:#{lr.deadline_at.to_i}:R>" : "No deadline"
      entries      = lr.loot_roll_entries.count
      "**#{lr.id}.** #{lr.title} — #{lr.min_roll}-#{lr.max_roll} — #{entries} rolls — closes #{deadline_str}"
    end

    embed = {
      title:       I18n.t("discord.commands.loot.list_title", guild: @guild.name),
      description: lines.join("\n"),
      color:       0x5865F2,
      footer:      { text: "GuildSync Loot Rolls • Use /loot view loot_id:<id> for details" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_view
    opts    = subcommand_options(@interaction)
    roll_id = opts["loot_id"].to_i

    loot_roll = @guild.loot_rolls.find_by(id: roll_id)
    return ephemeral_response(I18n.t("discord.commands.loot.not_found")) unless loot_roll

    entries       = loot_roll.loot_roll_entries.active.ordered_by_roll
    total_entries = entries.count
    highest       = loot_roll.highest_roll
    status        = loot_roll.currently_open? ? "🟢 Open" : "🔴 Closed"

    top_rolls = entries.limit(10).map.with_index(1) do |e, i|
      marker = e.roll_value == highest ? "🏆 " : ""
      "#{i}. #{marker}#{e.display_name} — #{e.roll_value}"
    end

    description = "**Range:** #{loot_roll.min_roll}–#{loot_roll.max_roll}"
    if loot_roll.deadline_at
      description += "\n**Deadline:** <t:#{loot_roll.deadline_at.to_i}:R>"
    end
    description += "\n**Status:** #{status}"

    if loot_roll.winner_entry
      description += "\n\n🏆 **Winner:** #{loot_roll.winner_entry.display_name} (#{loot_roll.winner_entry.roll_value})"
    end

    fields = []
    if total_entries > 0
      fields << {
        name:   "🎲 Top Rolls (#{total_entries} total)",
        value:  top_rolls.join("\n"),
        inline: false
      }
    else
      fields << { name: "🎲 Rolls", value: "No rolls yet.", inline: false }
    end

    embed = {
      title:       "🎲 #{loot_roll.title}",
      description: description,
      color:       loot_roll.currently_open? ? 0x00FF00 : 0xFF0000,
      fields:      fields,
      footer:      { text: "GuildSync Loot Roll ##{loot_roll.id}" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_close
    guard = require_officer!(@guild, @user, @guild_member)
    return guard if guard

    opts    = subcommand_options(@interaction)
    roll_id = opts["loot_id"].to_i

    loot_roll = @guild.loot_rolls.find_by(id: roll_id)
    return ephemeral_response(I18n.t("discord.commands.loot.not_found")) unless loot_roll

    unless loot_roll.open?
      return ephemeral_response(I18n.t("discord.commands.loot.already_closed"))
    end

    interaction_token = @interaction_token
    guild             = @guild
    user              = @user

    DiscordCommandJob.perform_later(
      "DiscordLootCommandService",
      "process_close",
      interaction_token,
      guild.id,
      user.id,
      { loot_id: loot_roll.id }
    )

    deferred_response(ephemeral: true)
  end

  # Called by DiscordCommandJob
  def process_close(opts)
    loot_roll = @guild.loot_rolls.find(opts[:loot_id])

    # Idempotency: skip closing if already closed on a prior attempt
    unless loot_roll.open?
      winner_text = loot_roll.winner_entry ?
        I18n.t("discord.commands.loot.closed_winner",
               item: loot_roll.title, winner: loot_roll.winner_entry.display_name,
               roll: loot_roll.winner_entry.roll_value) :
        I18n.t("discord.commands.loot.closed_no_entries", item: loot_roll.title)
      send_followup(@interaction_token, winner_text, ephemeral: true)
      return
    end

    loot_roll.close_and_determine_winner!
    service = DiscordLootRollService.new(loot_roll.reload)
    service.update_loot_roll_message

    winner_text = if loot_roll.winner_entry
      I18n.t("discord.commands.loot.closed_winner",
             item: loot_roll.title, winner: loot_roll.winner_entry.display_name,
             roll: loot_roll.winner_entry.roll_value)
    else
      I18n.t("discord.commands.loot.closed_no_entries", item: loot_roll.title)
    end

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "loot_roll_closed",
      description: "Closed loot roll via Discord: \"#{loot_roll.title}\"",
      subject:     loot_roll,
      title:       loot_roll.title
    )

    send_followup(@interaction_token, winner_text, ephemeral: true)
  end
end
