require "rest-client"
require "json"

class DiscordPollService
  DISCORD_API_BASE = "https://discord.com/api/v10"

  def initialize(poll)
    @poll = poll
    @guild = poll.guild
    @discord_setting = @guild.guild_discord_setting
    @bot_token = @discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
  end

  def post_poll
    unless @discord_setting&.connected?
      raise "Discord not connected for this guild"
    end

    channel_id = @poll.discord_channel_id || @discord_setting.polls_channel_id
    unless channel_id.present?
      raise "Polls channel not configured. Please configure it in guild settings."
    end

    embed = build_embed
    components = build_buttons
    
    # Build role mentions if any are selected (uniq to prevent duplicates)
    content = ""
    if @poll.discord_role_mentions.present? && @poll.discord_role_mentions.any?
      # Get the guild's discord_guild_id for @everyone detection
      discord_guild_id = @discord_setting&.discord_guild_id
      
      # Also get role names to check for @everyone by name
      role_names_by_id = @guild.discord_role_syncs.where(role_id: @poll.discord_role_mentions).pluck(:role_id, :role_name).to_h
      
      content = @poll.discord_role_mentions.uniq.map do |id|
        role_name = role_names_by_id[id.to_s]
        
        # @everyone role: either matches guild ID or has @everyone as name
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
    @poll.update!(
      discord_message_id: message_data["id"],
      discord_channel_id: channel_id
    )

    message_data
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "Failed to post poll to Discord: #{e.response.code} - #{e.response.body}"
    raise "Failed to post poll to Discord: #{e.response.body}"
  end

  def update_poll_message
    return unless @poll.discord_message_id.present? && @poll.discord_channel_id.present?

    embed = build_embed
    components = build_buttons

    RestClient.patch(
      "#{DISCORD_API_BASE}/channels/#{@poll.discord_channel_id}/messages/#{@poll.discord_message_id}",
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
    Rails.logger.error "Failed to update poll message on Discord: #{e.response.code} - #{e.response.body}"
    # Don't raise - this is called frequently and we don't want to break the app
  end

  private

  def build_embed
    vote_counts = @poll.vote_counts
    vote_percentages = @poll.vote_percentages
    total_votes = @poll.total_votes

    # Format deadline as Discord timestamp
    deadline_timestamp = @poll.deadline.to_i
    deadline_formatted = "<t:#{deadline_timestamp}:F>"

    # Build description
    description = @poll.description.present? ? @poll.description : "No description provided."
    description += "\n\n**⏰ Deadline:** #{deadline_formatted}"
    
    if @poll.anonymous?
      description += "\n**🔒 Anonymous Voting:** Yes"
    end

    # Build fields for vote counts
    fields = []
    
    if total_votes > 0
      # Get voter lists if not anonymous
      yes_voters = []
      no_voters = []
      maybe_voters = []
      
      unless @poll.anonymous?
        cache = {}
        yes_voters = @poll.poll_votes.where(choice: :yes).includes(:user).map { |v|
          voter_label(v, cache)
        }
        no_voters = @poll.poll_votes.where(choice: :no).includes(:user).map { |v|
          voter_label(v, cache)
        }
        maybe_voters = @poll.poll_votes.where(choice: :maybe).includes(:user).map { |v|
          voter_label(v, cache)
        }
      end
      
      # Yes field
      yes_value = "#{vote_counts[:yes]} votes (#{vote_percentages[:yes]}%)"
      yes_value += "\n#{yes_voters.join(', ')}" if yes_voters.any?
      fields << {
        name: "✅ Yes",
        value: yes_value.presence || "0 votes (0%)",
        inline: true
      }
      
      # No field
      no_value = "#{vote_counts[:no]} votes (#{vote_percentages[:no]}%)"
      no_value += "\n#{no_voters.join(', ')}" if no_voters.any?
      fields << {
        name: "❌ No",
        value: no_value.presence || "0 votes (0%)",
        inline: true
      }
      
      # Maybe field
      maybe_value = "#{vote_counts[:maybe]} votes (#{vote_percentages[:maybe]}%)"
      maybe_value += "\n#{maybe_voters.join(', ')}" if maybe_voters.any?
      fields << {
        name: "🤔 Maybe",
        value: maybe_value.presence || "0 votes (0%)",
        inline: true
      }
    else
      fields << {
        name: "📊 Results",
        value: "No votes yet. Be the first to vote!",
        inline: false
      }
    end

    # Status field
    status = @poll.open? ? "🟢 Open" : "🔴 Closed"
    fields << {
      name: "Status",
      value: status,
      inline: true
    }

    fields << {
      name: "Total Votes",
      value: total_votes.to_s,
      inline: true
    }

    {
      title: "📊 #{@poll.title}",
      description: description,
      color: @poll.open? ? 0x00FF00 : 0xFF0000, # Green if open, red if closed
      fields: fields,
      timestamp: @poll.deadline.iso8601,
      footer: {
        text: "GuildSync Poll • #{@guild.discord_server_display_name} • Click buttons below to vote"
      }
    }
  end

  def voter_label(vote, cache)
    if vote.user
      DiscordGuildMemberLabel.for_user_in_guild(user: vote.user, guild: @guild, cache: cache)
    else
      vote.discord_username.presence || "Discord User"
    end
  end

  def build_buttons
    return [] unless @poll.open?

    [
      {
        type: 1, # ACTION_ROW
        components: [
          {
            type: 2, # BUTTON
            style: 3, # SUCCESS (green)
            label: "✅ Yes",
            custom_id: "poll_vote_#{@poll.id}_yes"
          },
          {
            type: 2, # BUTTON
            style: 4, # DANGER (red)
            label: "❌ No",
            custom_id: "poll_vote_#{@poll.id}_no"
          },
          {
            type: 2, # BUTTON
            style: 2, # SECONDARY (gray)
            label: "🤔 Maybe",
            custom_id: "poll_vote_#{@poll.id}_maybe"
          }
        ]
      }
    ]
  end
end

