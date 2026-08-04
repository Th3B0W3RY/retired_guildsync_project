# frozen_string_literal: true

require "rest-client"
require "json"

# Handles all Discord interactions for the React Roles feature:
#   - Posting / updating the embed message in the configured channel
#   - Adding the bot's own reactions so users can click them
#   - Assigning / removing Discord roles when users add / remove reactions
#   - Removing the embed when the feature is disabled
#
# Follows the DiscordPollService pattern: initialized with the guild,
# reads @bot_token from GuildDiscordSetting or ENV fallback.
class DiscordReactRolesService
  DISCORD_API_BASE = "https://discord.com/api/v10"
  EMBED_COLOR = 0x5865F2  # Discord blurple

  def initialize(guild)
    @guild = guild
    @discord_setting = guild.guild_discord_setting
    @discord_service = DiscordService.new
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Deploy: post or update the embed and seed reactions
  # ──────────────────────────────────────────────────────────────────────────

  # Posts (or updates) the react roles embed in the configured channel and
  # seeds the bot's own reactions so users have clickable emoji buttons.
  # The resulting message_id and channel_id are persisted on every ReactRole
  # record so the gateway handler can find them without extra joins.
  def deploy_embed
    react_roles = @guild.react_roles.ordered
    raise "No react roles configured for this guild" if react_roles.empty?

    channel_id = react_roles.first.channel_id
    raise "React roles channel not set" unless channel_id.present?

    embed = build_embed(react_roles)

    existing_message_id = react_roles.first.message_id

    if existing_message_id.present?
      result = @discord_service.update_message(channel_id, existing_message_id, nil, embed: embed)
      # update_message returns nil on 404 (message deleted from Discord), fall through to re-post
      if result.nil?
        message_id = post_new_message(channel_id, embed, react_roles)
      else
        message_id = existing_message_id
        # Ensure bot reactions are still on the message (they may have been removed)
        add_bot_reactions(channel_id, message_id, react_roles)
      end
    else
      message_id = post_new_message(channel_id, embed, react_roles)
    end

    # Persist channel_id and message_id on all ReactRole rows for this guild
    @guild.react_roles.update_all(channel_id: channel_id, message_id: message_id)

    Rails.logger.info "[ReactRoles] Deployed embed for guild #{@guild.id} → message #{message_id} in channel #{channel_id}"
    message_id
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Reaction event handlers (called from DiscordBotService gateway handlers)
  # ──────────────────────────────────────────────────────────────────────────

  # Called when a user adds a reaction. Assigns the matching Discord role.
  def handle_reaction_add(user_id, message_id, emoji_name, emoji_id)
    react_role = find_react_role_by_emoji(message_id, emoji_name, emoji_id)
    return unless react_role

    discord_guild_id = resolved_discord_guild_id
    return unless discord_guild_id.present?

    @discord_service.add_role_to_member(discord_guild_id, user_id, react_role.role_id)
    Rails.logger.info "[ReactRoles] Added role #{react_role.role_id} to user #{user_id} in guild #{@guild.id}"
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "[ReactRoles] Failed to add role #{react_role&.role_id} to user #{user_id}: #{e.response.code} #{e.response.body}"
  rescue => e
    Rails.logger.error "[ReactRoles] handle_reaction_add error: #{e.class}: #{e.message}"
  end

  # Called when a user removes a reaction. Removes the matching Discord role.
  def handle_reaction_remove(user_id, message_id, emoji_name, emoji_id)
    react_role = find_react_role_by_emoji(message_id, emoji_name, emoji_id)
    return unless react_role

    discord_guild_id = resolved_discord_guild_id
    return unless discord_guild_id.present?

    @discord_service.remove_role_from_member(discord_guild_id, user_id, react_role.role_id)
    Rails.logger.info "[ReactRoles] Removed role #{react_role.role_id} from user #{user_id} in guild #{@guild.id}"
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "[ReactRoles] Failed to remove role #{react_role&.role_id} from user #{user_id}: #{e.response.code} #{e.response.body}"
  rescue => e
    Rails.logger.error "[ReactRoles] handle_reaction_remove error: #{e.class}: #{e.message}"
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Remove: delete the embed from Discord
  # ──────────────────────────────────────────────────────────────────────────

  def remove_embed
    react_role_with_message = @guild.react_roles.where.not(message_id: nil).first
    return unless react_role_with_message

    channel_id = react_role_with_message.channel_id
    message_id = react_role_with_message.message_id

    @discord_service.delete_message(channel_id, message_id)
    @guild.react_roles.update_all(message_id: nil, channel_id: nil)
    Rails.logger.info "[ReactRoles] Removed embed #{message_id} for guild #{@guild.id}"
  rescue => e
    Rails.logger.error "[ReactRoles] remove_embed error: #{e.class}: #{e.message}"
  end

  private

  def build_embed(react_roles)
    fields = react_roles.map do |rr|
      {
        name: "#{rr.display_emoji}  #{rr.role_name}",
        value: "React with #{rr.display_emoji} to receive this role.",
        inline: false
      }
    end

    {
      title: "React to Get Roles",
      description: "React with an emoji below to be assigned the corresponding Discord role. Remove your reaction to lose the role.",
      color: EMBED_COLOR,
      fields: fields,
      footer: { text: "Powered by GuildSync • React roles are applied automatically" }
    }
  end

  def post_new_message(channel_id, embed, react_roles)
    result = @discord_service.send_message(channel_id, nil, embed: embed)
    message_id = result["id"]
    add_bot_reactions(channel_id, message_id, react_roles)
    message_id
  end

  # Seeds the bot's own reactions in position order.
  # Rate-limit: Discord allows 1 reaction per 250 ms; we sleep between calls.
  def add_bot_reactions(channel_id, message_id, react_roles)
    react_roles.each_with_index do |rr, index|
      sleep(0.3) if index > 0  # avoid rate-limit on rapid sequential reactions
      @discord_service.create_reaction(channel_id, message_id, rr.api_emoji)
    end
  end

  # Find which ReactRole matches the incoming emoji from a gateway event.
  # Compares by message_id first (fast index lookup), then by emoji identity.
  def find_react_role_by_emoji(message_id, emoji_name, emoji_id)
    candidates = @guild.react_roles.where(message_id: message_id)
    return nil if candidates.empty?

    candidates.detect do |rr|
      if rr.is_custom_emoji?
        # Custom emoji: match by Discord snowflake ID
        emoji_id.present? && rr.emoji_id.to_s == emoji_id.to_s
      else
        # Unicode emoji: match by character name
        rr.emoji_name == emoji_name
      end
    end
  end

  def resolved_discord_guild_id
    @guild.discord_id.presence || @discord_setting&.discord_guild_id.presence
  end
end
