# frozen_string_literal: true

class AllianceMessagesChannel < ApplicationCable::Channel
  def subscribed
    alliance_id = params[:alliance_id].to_i
    message_type = params[:message_type].to_s

    unless %w[all_members gm_only].include?(message_type)
      reject
      return
    end

    if alliance_id <= 0
      reject
      return
    end

    alliance = Alliance.find_by(id: alliance_id)
    unless alliance
      reject
      return
    end

    unless alliance.alliance_members.where(user: current_user, status: :active).exists?
      reject
      return
    end

    if message_type == "gm_only" && !gm_in_alliance?(current_user, alliance)
      reject
      return
    end

    stream_from self.class.stream_name(alliance_id, message_type)
  end

  def unsubscribed
    # no-op
  end

  def self.stream_name(alliance_id, message_type)
    "alliance_messages:#{alliance_id}:#{message_type}"
  end

  def self.broadcast_new_message(alliance_id, message_type, message_payload)
    ActionCable.server.broadcast(
      stream_name(alliance_id, message_type),
      { type: "message", message: message_payload }
    )
  end

  private

  def gm_in_alliance?(user, alliance)
    user.owned_guilds.any? { |guild| alliance.active_guild_ids.include?(guild.id) }
  end
end
