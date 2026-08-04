# frozen_string_literal: true

# Handles the /alliance slash command and subcommands.
#
# Subcommands:
#   /alliance info     — show linked alliance summary + web link (guild must be in an alliance)
#   /alliance hub      — GuildSync alliances page URL
#   /alliance requests — pending join requests for this alliance (leader / GM / officers)
class DiscordAllianceCommandService
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
    when :hub      then handle_hub
    when :requests then handle_requests
    else ephemeral_response(I18n.t("discord.commands.errors.unknown_subcommand"))
    end
  end

  private

  def handle_info
    ag = @guild.alliance_guild
    unless ag&.active?
      return ephemeral_response(I18n.t("discord.commands.alliance.not_in_alliance"))
    end

    alliance = ag.alliance
    url = Rails.application.routes.url_helpers.alliance_url(alliance, **app_url_options)
    embed = {
      title:       I18n.t("discord.commands.alliance.info_title", name: alliance.name),
      description: alliance.description.to_s.truncate(400).presence || I18n.t("discord.commands.alliance.no_description"),
      url:         url,
      color:       0x5865F2,
      fields:      [
        { name: I18n.t("discord.commands.alliance.field_guilds"), value: alliance.active_guild_count.to_s, inline: true },
        { name: I18n.t("discord.commands.alliance.field_hub"),     value: I18n.t("discord.commands.alliance.use_hub"), inline: false }
      ],
      footer:      { text: "GuildSync" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_hub
    url = Rails.application.routes.url_helpers.alliances_url(**app_url_options)
    ephemeral_response(I18n.t("discord.commands.alliance.hub_message", url: url))
  end

  def handle_requests
    ag = @guild.alliance_guild
    unless ag&.active?
      return ephemeral_response(I18n.t("discord.commands.alliance.not_in_alliance"))
    end

    alliance = ag.alliance
    unless discord_can_manage_alliance_invites?(alliance, @guild, @user)
      return ephemeral_response(I18n.t("discord.commands.alliance.requests_unauthorized"))
    end

    pending = alliance.alliance_join_requests.pending_requests.includes(:requesting_guild)
    if pending.empty?
      return ephemeral_response(I18n.t("discord.commands.alliance.no_pending_requests"))
    end

    lines = pending.map do |jr|
      "- **#{jr.requesting_guild.name}** (request ##{jr.id})"
    end

    hub = Rails.application.routes.url_helpers.alliance_url(alliance, **app_url_options)
    body = I18n.t(
      "discord.commands.alliance.requests_body",
      count: pending.size,
      list: lines.join("\n"),
      url: hub
    )

    ephemeral_response(body)
  end

  def app_url_options
    opts = Rails.application.config.action_mailer.default_url_options&.dup || {}
    opts[:host] ||= ENV.fetch("APP_HOST", "localhost")
    opts[:protocol] ||= (Rails.env.production? ? "https" : "http")
    opts[:port] ||= ENV["APP_PORT"].presence
    opts.compact
  end

  # Authorization for Discord `/alliance` **join-request** listing (not web guild invites).
  # Web alliance **guild** invites are leader-only in `AllianceInvitesController`.
  def discord_can_manage_alliance_invites?(alliance, guild, user)
    return true if alliance.leader_user_id == user.id

    if guild.owner_id == user.id && alliance.active_guild_ids.include?(guild.id)
      return true
    end

    officer_member = alliance.alliance_members.find_by(user: user, role: :officer, status: :active)
    officer_member&.guild_id == guild.id
  end
end
