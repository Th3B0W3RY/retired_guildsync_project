# frozen_string_literal: true

# Handles the /guild slash command and all its subcommands.
#
# Subcommands:
#   /guild info     — member count, plan, games (any member)
#   /guild settings — guild settings overview (owner only)
#   /guild channels — configured Discord channel IDs (officer+)
class DiscordGuildCommandService
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
    when :info     then handle_info
    when :settings then handle_settings
    when :channels then handle_channels
    else ephemeral_response(I18n.t("discord.commands.errors.unknown_subcommand"))
    end
  end

  private

  def handle_info
    member_count = @guild.guild_members.active.count
    games        = @guild.games.pluck(:name).join(", ").presence || "None"
    plan_name    = @guild.owner&.current_plan&.name || "Unknown"
    owner_name   = @guild.owner&.display_name.presence || @guild.owner&.username || "Unknown"

    fields = [
      { name: "Owner",       value: owner_name,                inline: true },
      { name: "Members",     value: member_count.to_s,         inline: true },
      { name: "Plan",        value: plan_name,                 inline: true },
      { name: "Games",       value: games,                     inline: false },
      { name: "Discord",     value: @guild.guild_discord_setting&.connected? ? "Connected" : "Not connected", inline: true }
    ]

    if @guild.description.present?
      fields.unshift({ name: "Description", value: @guild.description.truncate(200), inline: false })
    end

    embed = {
      title:  I18n.t("discord.commands.guild.info_title", name: @guild.name),
      color:  0x5865F2,
      fields: fields,
      footer: { text: "GuildSync • guild-sync.net" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_settings
    guard = require_owner!(@guild, @user)
    return guard if guard

    setting = @guild.guild_discord_setting
    connected = setting&.connected? ? "Yes" : "No"

    fields = [
      { name: "Guild ID",       value: @guild.id.to_s, inline: true },
      { name: "Discord Connected", value: connected,  inline: true },
      { name: "Max Guilds",     value: (@guild.owner&.current_plan&.max_guilds || "∞").to_s, inline: true },
      { name: "Max Members",    value: (@guild.owner&.current_plan&.respond_to?(:max_members_per_guild) ? @guild.owner.current_plan.max_members_per_guild : "∞").to_s, inline: true }
    ]

    embed = {
      title:  I18n.t("discord.commands.guild.settings_title", name: @guild.name),
      color:  0x5865F2,
      fields: fields,
      footer: { text: "Full settings available at guild-sync.net" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_channels
    guard = require_officer!(@guild, @user, @guild_member)
    return guard if guard

    setting = @guild.guild_discord_setting
    not_set = I18n.t("discord.commands.guild.channel_not_set")

    fields = [
      { name: "Events",     value: setting&.events_channel_id.presence ? "<##{setting.events_channel_id}>" : not_set,     inline: true },
      { name: "Gear",       value: setting&.gear_channel_id.presence    ? "<##{setting.gear_channel_id}>" : not_set,       inline: true },
      { name: "Polls",      value: setting&.polls_channel_id.presence   ? "<##{setting.polls_channel_id}>" : not_set,      inline: true },
      { name: "Loot Rolls", value: setting&.loot_rolls_channel_id.presence ? "<##{setting.loot_rolls_channel_id}>" : not_set, inline: true }
    ]

    embed = {
      title:  I18n.t("discord.commands.guild.channels_title", name: @guild.name),
      color:  0x5865F2,
      fields: fields,
      footer: { text: "Configure channels at guild-sync.net/guilds/#{@guild.id}/settings" }
    }

    embed_response(embed, ephemeral: true)
  end
end
