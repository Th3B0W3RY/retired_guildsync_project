# frozen_string_literal: true

# Handles the /member slash command and all its subcommands.
#
# Subcommands:
#   /member list  [role:<member|moderator|admin>] — list guild members (any member)
#   /member info  user:@User — view a member's details (any member)
#   /member kick  user:@User [reason:<str>] — remove a member (officer+)
#   /member role  user:@User role:<member|moderator|admin> — change role (officer+)
class DiscordMemberCommandService
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
    when :list then handle_list
    when :info then handle_info
    when :kick then handle_kick
    when :role then handle_role
    else ephemeral_response(I18n.t("discord.commands.errors.unknown_subcommand"))
    end
  end

  private

  def handle_list
    opts        = subcommand_options(@interaction)
    role_filter = opts["role"].presence

    members = @guild.guild_members.active.includes(:user)
    members = members.where(role: role_filter) if role_filter.present?
    members = members.order(:role, created_at: :asc).limit(25)

    if members.empty?
      return ephemeral_response(I18n.t("discord.commands.member.none"))
    end

    lines = members.map do |gm|
      role_label = gm.role.capitalize
      joined     = gm.joined_at ? "<t:#{gm.joined_at.to_i}:D>" : "unknown"
      "**#{gm.user.display_name.presence || gm.user.username}** — #{role_label} — joined #{joined}"
    end

    total = @guild.guild_members.active.count
    embed = {
      title:       I18n.t("discord.commands.member.list_title", guild: @guild.name),
      description: lines.join("\n"),
      color:       0x5865F2,
      footer:      { text: "#{total} total active member#{total == 1 ? '' : 's'} • showing first 25" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_info
    opts              = subcommand_options(@interaction)
    target_discord_id = opts["user"].to_s.strip

    gm = find_guild_member_by_discord_id(target_discord_id)
    return ephemeral_response(I18n.t("discord.commands.member.not_found")) unless gm

    u       = gm.user
    name    = u.display_name.presence || u.username
    joined  = gm.joined_at ? "<t:#{gm.joined_at.to_i}:D>" : "unknown"

    latest_gear = u.gear_snapshots.where(guild: @guild).order(created_at: :desc).first

    fields = [
      { name: "Role",       value: gm.role.capitalize, inline: true },
      { name: "Status",     value: gm.status.capitalize, inline: true },
      { name: "Joined",     value: joined, inline: true },
      { name: "Gear",       value: latest_gear ? "<t:#{latest_gear.created_at.to_i}:D>" : "No snapshot", inline: true }
    ]

    embed = {
      title:  I18n.t("discord.commands.member.info_title", username: name),
      color:  0x5865F2,
      fields: fields,
      footer: { text: "GuildSync Member Profile" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_kick
    guard = require_officer!(@guild, @user, @guild_member)
    return guard if guard

    opts              = subcommand_options(@interaction)
    target_discord_id = opts["user"].to_s.strip
    reason            = opts["reason"].to_s.strip.presence

    gm = find_guild_member_by_discord_id(target_discord_id)
    return ephemeral_response(I18n.t("discord.commands.member.not_found")) unless gm

    if @guild.owner_id == gm.user_id
      return ephemeral_response(I18n.t("discord.commands.member.cannot_kick_owner"))
    end

    username = gm.user.display_name.presence || gm.user.username
    gm.destroy

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "member_kicked",
      description: "Kicked #{username} via Discord#{reason ? ": #{reason}" : ''}",
      title:       "Member kicked"
    )

    ephemeral_response(I18n.t("discord.commands.member.kicked", username: username))
  end

  def handle_role
    guard = require_officer!(@guild, @user, @guild_member)
    return guard if guard

    opts              = subcommand_options(@interaction)
    target_discord_id = opts["user"].to_s.strip
    new_role          = opts["role"].to_s.strip

    gm = find_guild_member_by_discord_id(target_discord_id)
    return ephemeral_response(I18n.t("discord.commands.member.not_found")) unless gm

    if @guild.owner_id == gm.user_id
      return ephemeral_response(I18n.t("discord.commands.member.cannot_demote_owner"))
    end

    unless GuildMember.roles.key?(new_role)
      return ephemeral_response(I18n.t("discord.commands.errors.generic"))
    end

    username = gm.user.display_name.presence || gm.user.username
    gm.update!(role: new_role)

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "member_role_updated",
      description: "Updated #{username}'s role to #{new_role} via Discord",
      title:       "Role updated"
    )

    ephemeral_response(I18n.t("discord.commands.member.role_updated", username: username, role: new_role.capitalize))
  end

  def find_guild_member_by_discord_id(discord_id)
    @guild.guild_members.active
          .joins(user: :user_discord_connection)
          .find_by(user_discord_connections: { discord_user_id: discord_id })
  end
end
