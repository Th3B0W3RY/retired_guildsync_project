# frozen_string_literal: true

# Alliance polls are announced per member guild (each guild's bot token + alliance poll channel).
# This service builds embeds/components and updates every linked Discord message after votes.
class DiscordAlliancePollService
  def initialize(alliance_poll)
    @poll = alliance_poll
  end

  def self.update_all_linked_messages(poll)
    new(poll).update_all_linked_messages
  end

  def self.delete_all_linked_messages(poll)
    new(poll).delete_all_linked_messages
  end

  def build_embed(guild: nil)
    vote_counts = @poll.vote_counts
    vote_percentages = @poll.vote_percentages
    total_votes = @poll.total_votes

    deadline_timestamp = @poll.deadline.to_i
    deadline_formatted = "<t:#{deadline_timestamp}:F>"

    description = @poll.description.present? ? @poll.description : "No description provided."
    description += "\n\n**⏰ Deadline:** #{deadline_formatted}"

    description += "\n**🔒 Anonymous Voting:** Yes" if @poll.anonymous?

    fields = []

    if total_votes.positive?
      yes_voters = []
      no_voters = []
      maybe_voters = []

      unless @poll.anonymous?
        cache = {}
        yes_voters   = voter_display_names(@poll.alliance_poll_votes.where(choice: :yes).includes(:user), guild, cache)
        no_voters    = voter_display_names(@poll.alliance_poll_votes.where(choice: :no).includes(:user), guild, cache)
        maybe_voters = voter_display_names(@poll.alliance_poll_votes.where(choice: :maybe).includes(:user), guild, cache)
      end

      yes_value = "#{vote_counts[:yes]} votes (#{vote_percentages[:yes]}%)"
      yes_value += "\n#{yes_voters.join(', ')}" if yes_voters.any?
      fields << { name: "✅ Yes", value: yes_value.presence || "0 votes (0%)", inline: true }

      no_value = "#{vote_counts[:no]} votes (#{vote_percentages[:no]}%)"
      no_value += "\n#{no_voters.join(', ')}" if no_voters.any?
      fields << { name: "❌ No", value: no_value.presence || "0 votes (0%)", inline: true }

      maybe_value = "#{vote_counts[:maybe]} votes (#{vote_percentages[:maybe]}%)"
      maybe_value += "\n#{maybe_voters.join(', ')}" if maybe_voters.any?
      fields << { name: "🤔 Maybe", value: maybe_value.presence || "0 votes (0%)", inline: true }
    else
      fields << {
        name: "📊 Results",
        value: "No votes yet. Be the first to vote!",
        inline: false
      }
    end

    status = @poll.open? ? "🟢 Open" : "🔴 Closed"
    fields << { name: "Status", value: status, inline: true }
    fields << { name: "Total Votes", value: total_votes.to_s, inline: true }

    server_suffix = guild ? " • #{guild.discord_server_display_name}" : ""

    {
      title: "📊 #{@poll.title}",
      url: poll_url,
      description: description,
      color: @poll.open? ? 0x00FF00 : 0xFF0000,
      fields: fields,
      timestamp: @poll.deadline.iso8601,
      footer: { text: "GuildSync Alliance Poll#{server_suffix} • Click buttons below to vote" }
    }
  end

  def build_buttons
    return [] unless @poll.open?

    [
      {
        type: 1,
        components: [
          {
            type: 2,
            style: 3,
            label: "✅ Yes",
            custom_id: "alliance_poll_vote_#{@poll.id}_yes"
          },
          {
            type: 2,
            style: 4,
            label: "❌ No",
            custom_id: "alliance_poll_vote_#{@poll.id}_no"
          },
          {
            type: 2,
            style: 2,
            label: "🤔 Maybe",
            custom_id: "alliance_poll_vote_#{@poll.id}_maybe"
          }
        ]
      }
    ]
  end

  def update_all_linked_messages
    @poll.reload
    components = build_buttons

    @poll.alliance_poll_discord_messages.includes(guild: :guild_discord_setting).find_each do |link|
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
      Rails.logger.warn "[DiscordAlliancePollService] update failed poll=#{@poll.id} guild=#{link.guild_id}: #{e.class}: #{e.message}"
    end
  end

  def delete_all_linked_messages
    @poll.alliance_poll_discord_messages.includes(guild: :guild_discord_setting).find_each do |link|
      setting = link.guild.guild_discord_setting
      token = bot_token_for(setting)
      next if token.blank?

      DiscordService.new(bot_token: token).delete_message(link.channel_id, link.discord_message_id)
    rescue StandardError => e
      Rails.logger.warn "[DiscordAlliancePollService] delete failed poll=#{@poll.id} guild=#{link.guild_id}: #{e.class}: #{e.message}"
    end
  end

  private

  def voter_display_names(votes_scope, guild, cache)
    votes_scope.map do |v|
      if v.user.nil?
        v.discord_username.presence || "Discord User"
      elsif guild.blank?
        v.user.name_for_discord_embed
      else
        DiscordGuildMemberLabel.for_user_in_guild(user: v.user, guild: guild, cache: cache)
      end
    end
  end

  def bot_token_for(setting)
    setting&.bot_token.presence || ENV["DISCORD_BOT_TOKEN"].presence
  end

  def poll_url
    Rails.application.routes.url_helpers.alliance_alliance_poll_url(
      @poll.alliance,
      @poll,
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
