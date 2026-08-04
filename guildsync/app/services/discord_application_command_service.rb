# frozen_string_literal: true

# Handles the /application slash command and all its subcommands.
#
# Subcommands (all officer+):
#   /application list                            — pending applications
#   /application view   application_id:<int>     — view one application
#   /application accept application_id:<int>     — accept, add to guild
#   /application reject application_id:<int> [reason:<str>]
class DiscordApplicationCommandService
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

    guard = require_officer!(@guild, @user, @guild_member)
    return guard if guard

    case subcommand_name(interaction)
    when :list   then handle_list
    when :view   then handle_view
    when :accept then handle_accept
    when :reject then handle_reject
    else ephemeral_response(I18n.t("discord.commands.errors.unknown_subcommand"))
    end
  end

  private

  def handle_list
    apps = @guild.guild_applications.pending.includes(:user).order(created_at: :asc).limit(15)

    if apps.empty?
      return ephemeral_response(I18n.t("discord.commands.application.none_pending"))
    end

    lines = apps.map do |a|
      applied = "<t:#{a.created_at.to_i}:R>"
      "**#{a.id}.** #{a.user.display_name.presence || a.discord_username} — applied #{applied}"
    end

    embed = {
      title:       I18n.t("discord.commands.application.list_title", guild: @guild.name),
      description: lines.join("\n"),
      color:       0x5865F2,
      footer:      { text: "Use /application view application_id:<id> for details" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_view
    opts   = subcommand_options(@interaction)
    app_id = opts["application_id"].to_i

    app = @guild.guild_applications.find_by(id: app_id)
    return ephemeral_response(I18n.t("discord.commands.application.not_found")) unless app

    username = app.user.display_name.presence || app.discord_username
    applied  = "<t:#{app.created_at.to_i}:F>"

    fields = [
      { name: "Applicant",      value: username,           inline: true },
      { name: "Discord",        value: app.discord_username, inline: true },
      { name: "Status",         value: app.status.capitalize, inline: true },
      { name: "Applied",        value: applied,            inline: false }
    ]

    if app.respond_to?(:message) && app.message.present?
      fields << { name: "Message", value: app.message.truncate(500), inline: false }
    end

    embed = {
      title:  I18n.t("discord.commands.application.view_title", id: app.id),
      color:  0x5865F2,
      fields: fields,
      footer: { text: "Use /application accept or reject to process" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_accept
    opts   = subcommand_options(@interaction)
    app_id = opts["application_id"].to_i

    app = @guild.guild_applications.find_by(id: app_id)
    return ephemeral_response(I18n.t("discord.commands.application.not_found")) unless app

    unless app.pending?
      return ephemeral_response(I18n.t("discord.commands.application.already_processed"))
    end

    interaction_token = @interaction_token
    guild             = @guild
    user              = @user

    DiscordCommandJob.perform_later(
      "DiscordApplicationCommandService",
      "process_accept",
      interaction_token,
      guild.id,
      user.id,
      { application_id: app.id }
    )

    deferred_response(ephemeral: true)
  end

  # Called by DiscordCommandJob
  def process_accept(opts)
    app = @guild.guild_applications.find(opts[:application_id])
    username = app.user.display_name.presence || app.discord_username

    # Idempotency: skip if already accepted on a prior attempt
    if app.accepted?
      send_followup(
        @interaction_token,
        I18n.t("discord.commands.application.accepted", username: username),
        ephemeral: true
      )
      return
    end

    ActiveRecord::Base.transaction do
      app.update!(status: :accepted)
      @guild.guild_members.find_or_create_by!(user: app.user) do |gm|
        gm.role   = :member
        gm.status = :active
      end
    end

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "application_accepted",
      description: "Accepted application from #{username} via Discord",
      subject:     app,
      title:       "Application accepted"
    )

    send_followup(
      @interaction_token,
      I18n.t("discord.commands.application.accepted", username: username),
      ephemeral: true
    )
  end

  def handle_reject
    opts   = subcommand_options(@interaction)
    app_id = opts["application_id"].to_i
    reason = opts["reason"].to_s.strip.presence

    app = @guild.guild_applications.find_by(id: app_id)
    return ephemeral_response(I18n.t("discord.commands.application.not_found")) unless app

    unless app.pending?
      return ephemeral_response(I18n.t("discord.commands.application.already_processed"))
    end

    username = app.user.display_name.presence || app.discord_username
    app.update!(status: :rejected)

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "application_rejected",
      description: "Rejected application from #{username} via Discord#{reason ? ": #{reason}" : ''}",
      subject:     app,
      title:       "Application rejected"
    )

    ephemeral_response(I18n.t("discord.commands.application.rejected", username: username))
  end
end
