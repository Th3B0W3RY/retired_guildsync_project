# frozen_string_literal: true

class PollsChannel < ApplicationCable::Channel
  def subscribed
    poll_id = params[:poll_id].to_i
    if poll_id <= 0
      reject
      return
    end

    poll = Poll.find_by(id: poll_id)
    unless poll
      reject
      return
    end

    guild = poll.guild
    unless current_user && (guild.members.include?(current_user) || guild.owner == current_user)
      reject
      return
    end

    stream_for poll
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
