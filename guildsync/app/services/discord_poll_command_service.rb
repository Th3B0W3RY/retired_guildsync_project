# frozen_string_literal: true

require "rest-client"

# Handles the /poll slash command and all its subcommands.
#
# Subcommands:
#   /poll create  question:<str> option_a:<str> option_b:<str> [option_c:<str>]
#                 [deadline_hours:<int>] [anonymous:<bool>]
#   /poll list    — list active polls in this guild (ephemeral)
#   /poll results poll_id:<int> — view poll results (ephemeral)
class DiscordPollCommandService
  include DiscordCommandHelpers

  # Entry point called from DiscordWebhooksController.
  # Returns a Discord interaction response hash to be rendered immediately,
  # then runs deferred background work when needed.
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
    when :create  then handle_create
    when :list    then handle_list
    when :results then handle_results
    else ephemeral_response(I18n.t("discord.commands.errors.unknown_subcommand"))
    end
  end

  private

  def handle_create
    guard = require_officer!(@guild, @user, @guild_member)
    return guard if guard

    limit_guard = enforce_plan_limit!(@guild, :polls)
    return limit_guard if limit_guard

    unless @guild.guild_discord_setting&.polls_channel_configured?
      return ephemeral_response(I18n.t("discord.commands.poll.no_channel"))
    end

    opts = subcommand_options(@interaction)

    question      = opts["question"].to_s.strip
    option_a      = opts["option_a"].to_s.strip
    option_b      = opts["option_b"].to_s.strip
    option_c      = opts["option_c"].to_s.strip.presence
    deadline_hrs  = [opts["deadline_hours"].to_i, 1].max
    anonymous     = opts["anonymous"] == true

    if question.blank? || option_a.blank? || option_b.blank?
      return ephemeral_response(I18n.t("discord.commands.poll.missing_fields"))
    end

    # Build description from options so voters know what they're voting on.
    # The Poll model uses Yes / No / Maybe — we map the provided options accordingly.
    option_text = "**A:** #{option_a} (Yes)\n**B:** #{option_b} (No)"
    option_text += "\n**C:** #{option_c} (Maybe)" if option_c

    description = option_text
    deadline    = deadline_hrs.hours.from_now

    interaction_token = @interaction_token
    guild             = @guild
    user              = @user

    DiscordCommandJob.perform_later(
      "DiscordPollCommandService",
      "process_create",
      interaction_token,
      guild.id,
      user.id,
      {
        question: question,
        description: description,
        deadline: deadline.to_s,
        anonymous: anonymous
      }
    )

    deferred_response(ephemeral: true)
  end

  # Called by DiscordCommandJob
  def process_create(opts)
    poll = @guild.polls.create!(
      title:       opts[:question],
      description: opts[:description],
      deadline:    Time.zone.parse(opts[:deadline]),
      anonymous:   opts[:anonymous],
      creator:     @user
    )

    service = DiscordPollService.new(poll)
    service.post_poll

    GuildActivityLogger.log(
      guild:       @guild,
      user:        @user,
      action_type: "poll_created",
      description: "Created poll via Discord: \"#{opts[:question]}\"",
      subject:     poll,
      title:       opts[:question]
    )

    send_followup(
      @interaction_token,
      I18n.t("discord.commands.poll.created", title: opts[:question], channel: "#polls"),
      ephemeral: true
    )
  end

  def handle_list
    polls = @guild.polls.open.ordered.limit(10)

    if polls.empty?
      return ephemeral_response(I18n.t("discord.commands.poll.none_active"))
    end

    lines = polls.map do |p|
      deadline_ts = "<t:#{p.deadline.to_i}:R>"
      "**#{p.id}.** #{p.title} — closes #{deadline_ts} — #{p.total_votes} votes"
    end

    embed = {
      title:       I18n.t("discord.commands.poll.list_title", guild: @guild.name),
      description: lines.join("\n"),
      color:       0x5865F2,
      footer:      { text: "GuildSync Polls • Use /poll results poll_id:<id> to view results" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_results
    opts    = subcommand_options(@interaction)
    poll_id = opts["poll_id"].to_i

    poll = @guild.polls.find_by(id: poll_id)
    return ephemeral_response(I18n.t("discord.commands.poll.not_found")) unless poll

    counts      = poll.vote_counts
    percentages = poll.vote_percentages
    total       = poll.total_votes
    status      = poll.open? ? "🟢 Open" : "🔴 Closed"

    fields = [
      { name: "✅ Yes",    value: "#{counts[:yes]} (#{percentages[:yes]}%)",   inline: true },
      { name: "❌ No",     value: "#{counts[:no]} (#{percentages[:no]}%)",     inline: true },
      { name: "🤔 Maybe", value: "#{counts[:maybe]} (#{percentages[:maybe]}%)", inline: true },
      { name: "Total",    value: total.to_s, inline: true },
      { name: "Status",   value: status,     inline: true }
    ]

    if poll.anonymous?
      fields << { name: "🔒 Anonymous", value: "Yes", inline: true }
    end

    embed = {
      title:  "📊 #{poll.title}",
      color:  poll.open? ? 0x00FF00 : 0xFF0000,
      fields: fields,
      footer: { text: "GuildSync Poll ##{poll.id}" }
    }

    embed_response(embed, ephemeral: true)
  end
end
