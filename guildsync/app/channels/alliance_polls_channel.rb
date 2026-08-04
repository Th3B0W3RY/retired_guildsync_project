# frozen_string_literal: true

class AlliancePollsChannel < ApplicationCable::Channel
  # Called after any successful vote (web UI or Discord) so Action Cable subscribers refresh counts.
  def self.broadcast_vote_update(poll)
    poll.reload
    msg = {
      type:             "vote_update",
      vote_counts:      poll.vote_counts,
      vote_percentages: poll.vote_percentages,
      total_votes:      poll.total_votes
    }
    msg[:voters_by_choice] = poll.voters_display_names_by_choice unless poll.anonymous?

    broadcast_to(poll, msg)
  end

  def subscribed
    poll_id = params[:alliance_poll_id].to_i
    if poll_id <= 0
      reject
      return
    end

    poll = AlliancePoll.find_by(id: poll_id)
    unless poll
      reject
      return
    end

    alliance = poll.alliance
    unless alliance.alliance_members.where(user: current_user, status: :active).exists?
      reject
      return
    end

    stream_for poll
  end

  def unsubscribed
    # no-op
  end
end
