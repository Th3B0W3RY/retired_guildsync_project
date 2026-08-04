# frozen_string_literal: true

require "rest-client"

# Handles the /invite slash command.
#
# Usage:
#   /invite user:@DiscordUser [message:<optional text>]
#
# Flow:
#   1. Resolve invoking user and guild via Discord guild_id.
#   2. Resolve the mentioned Discord user from Discord's resolved payload.
#   3. Generate a one-time-use GuildInviteLink.
#   4. Send a DM to the target user via the bot with the join link.
#   5. Reply ephemerally to the inviter confirming the DM was sent.
#
# Permission: any active guild member can invite (officers/owners needed
# only when guild is not open to applications — currently always allowed
# to keep parity with the web invite flow).
class DiscordInviteCommandService
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

    handle_invite
  end

  private

  def handle_invite
    opts              = command_options(@interaction)
    target_discord_id = opts["user"].to_s.strip
    personal_message  = opts["message"].to_s.strip.presence

    if target_discord_id.blank?
      return ephemeral_response(I18n.t("discord.commands.invite.no_user"))
    end

    # Prevent self-invites
    invoker_discord_id = @interaction.dig("member", "user", "id")
    if target_discord_id == invoker_discord_id
      return ephemeral_response(I18n.t("discord.commands.invite.self_invite"))
    end

    # Prevent re-inviting existing members
    existing_member = @guild.guild_members
                            .joins(:user)
                            .joins("JOIN user_discord_connections ON user_discord_connections.user_id = users.id")
                            .where(user_discord_connections: { discord_user_id: target_discord_id }, status: :active)
                            .exists?

    if existing_member
      return ephemeral_response(I18n.t("discord.commands.invite.already_member"))
    end

    # HIGH PRIORITY: Ensure target has a GuildSync account (UserDiscordConnection)
    target_conn = UserDiscordConnection.find_by(discord_user_id: target_discord_id)
    unless target_conn
      return ephemeral_response(I18n.t("discord.commands.errors.user_not_linked"))
    end

    interaction_token = @interaction_token
    guild             = @guild
    user              = @user

    DiscordCommandJob.perform_later(
      "DiscordInviteCommandService",
      "process_invite",
      interaction_token,
      guild.id,
      user.id,
      {
        target_discord_id: target_discord_id,
        personal_message: personal_message
      }
    )

    deferred_response(ephemeral: true)
  end

  # Called by DiscordCommandJob
  def process_invite(opts)
    target_discord_id = opts[:target_discord_id]
    personal_message  = opts[:personal_message]

    if @guild.invite_links_at_capacity?
      send_followup(
        @interaction_token,
        I18n.t("join.invite_links_limit", count: Guild::MAX_ACTIVE_INVITE_LINKS),
        ephemeral: true
      )
      return
    end

    invite_link = @guild.guild_invite_links.create!(
      created_by: @user,
      expires_at: 7.days.from_now
    )

    join_url = Rails.application.routes.url_helpers.join_guild_url(
      invite_link.token,
      host: ENV.fetch("APP_HOST", "guild-sync.net"),
      protocol: "https"
    )

    bot_token = @guild.guild_discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
    service   = DiscordService.new(bot_token: bot_token)

    dm_lines = []
    dm_lines << I18n.t("discord.commands.invite.dm_intro",
                       inviter: @user.display_name.presence || @user.username,
                       guild:   @guild.name)
    dm_lines << ""
    dm_lines << personal_message if personal_message
    dm_lines << ""
    dm_lines << I18n.t("discord.commands.invite.dm_link", url: join_url)
    dm_lines << I18n.t("discord.commands.invite.dm_expiry")

    service.send_dm(target_discord_id, dm_lines.compact.join("\n"))

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "member_invited",
      description: "Invited Discord user #{target_discord_id} via Discord slash command",
      title:       "Discord invite"
    )

    send_followup(
      @interaction_token,
      I18n.t("discord.commands.invite.sent", discord_user_id: target_discord_id),
      ephemeral: true
    )
  rescue RestClient::ExceptionWithResponse => e
    # Discord DMs can fail if the target has DMs disabled
    if e.response.code == 403
      Rails.logger.warn "[DiscordInviteCommand] DM blocked by user #{target_discord_id}: #{e.message}"
      send_followup(
        @interaction_token,
        I18n.t("discord.commands.invite.dm_disabled"),
        ephemeral: true
      )
    else
      Rails.logger.error "[DiscordInviteCommand] DM error (#{e.response.code}): #{e.message}"
      send_followup(@interaction_token, I18n.t("discord.commands.errors.generic"), ephemeral: true)
    end
  end
end
