# frozen_string_literal: true

module Guilds
  # Weighted leaderboard across guilds the viewer belongs to: on-time event attendance,
  # poll votes, and completed loot-roll entries (mega systems plan — events/polls heavy, loot minor).
  class MemberLeaderboardScores
    WEIGHT_EVENT_ON_TIME = 10
    WEIGHT_POLL_VOTE = 10
    WEIGHT_LOOT_CLOSED_ENTRY = 1

    def self.call(user_guild_ids:)
      new(user_guild_ids).call
    end

    def initialize(user_guild_ids)
      @guild_ids = Array(user_guild_ids).map(&:to_i).uniq
    end

    def call
      return [] if @guild_ids.empty?

      scores = Hash.new { |h, k| h[k] = { score: 0, display_name: nil } }

      add_event_scores!(scores)
      add_poll_scores!(scores)
      add_loot_scores!(scores)

      scores.map do |compound_key, data|
        _identity, server_name = compound_key
        {
          discord_username: data[:display_name].presence || "—",
          discord_server_name: server_name,
          score: data[:score],
          participation_count: data[:score]
        }
      end.sort_by { |e| -e[:score] }
    end

    private

    def guild_server_label(guild)
      guild.guild_discord_setting&.discord_guild_name.presence || guild.name
    end

    def add_event_scores!(scores)
      DiscordEventParticipation
        .joins(event: :guild)
        .where(events: { guild_id: @guild_ids, status: %i[in_progress completed] })
        .where(on_time: true)
        .includes(event: { guild: :guild_discord_setting })
        .find_each do |p|
          guild = p.event.guild
          server = guild_server_label(guild)
          key = [ [ :discord, p.discord_user_id.to_s ], server ]
          row = scores[key]
          row[:score] += WEIGHT_EVENT_ON_TIME
          row[:display_name] ||= p.discord_username
        end
    end

    def add_poll_scores!(scores)
      PollVote
        .joins(poll: :guild)
        .where(polls: { guild_id: @guild_ids })
        .includes(:user, poll: { guild: :guild_discord_setting })
        .find_each do |vote|
          guild = vote.poll.guild
          server = guild_server_label(guild)
          if vote.discord_user_id.present?
            key = [ [ :discord, vote.discord_user_id.to_s ], server ]
            row = scores[key]
            row[:score] += WEIGHT_POLL_VOTE
            row[:display_name] ||= vote.discord_username.presence || vote.user&.username
          elsif vote.user_id.present?
            key = [ [ :user, vote.user_id.to_s ], server ]
            row = scores[key]
            row[:score] += WEIGHT_POLL_VOTE
            row[:display_name] ||= vote.user&.username
          end
        end
    end

    def add_loot_scores!(scores)
      LootRollEntry
        .joins(:loot_roll)
        .where(loot_rolls: { guild_id: @guild_ids, status: LootRoll.statuses[:closed] })
        .where(is_reroll: false)
        .includes(loot_roll: { guild: :guild_discord_setting })
        .find_each do |entry|
          guild = entry.loot_roll.guild
          server = guild_server_label(guild)
          key = [ [ :discord, entry.discord_user_id.to_s ], server ]
          row = scores[key]
          row[:score] += WEIGHT_LOOT_CLOSED_ENTRY
          row[:display_name] ||= entry.display_name
        end
    end
  end
end
