# frozen_string_literal: true

class AllianceLootRollsChannel < ApplicationCable::Channel
  def self.broadcast_update(roll)
    return unless roll&.persisted?

    roll.reload
    entries = roll.alliance_loot_roll_entries.order(roll_value: :desc).map do |entry|
      e = {
        id:           entry.id,
        display_name: entry.display_name,
        mask_name:    roll.anonymous?,
        roll_value:   entry.roll_value,
        is_winner:    entry.id == roll.winner_entry_id
      }
      e[:user_id] = entry.user_id if !roll.anonymous? && entry.user_id.present?
      e
    end

    broadcast_to(roll, {
      type:             "alliance_loot_roll_update",
      entries:          entries,
      total_entries:    roll.total_entries,
      status:           roll.status,
      currently_open:   roll.currently_open?,
      winner_id:        roll.winner_entry_id
    })
  end

  def subscribed
    roll_id = params[:alliance_loot_roll_id].to_i
    if roll_id <= 0
      reject
      return
    end

    roll = AllianceLootRoll.find_by(id: roll_id)
    unless roll
      reject
      return
    end

    alliance = roll.alliance
    unless alliance.alliance_members.where(user: current_user, status: :active).exists?
      reject
      return
    end

    stream_for roll
  end

  def unsubscribed
    # no-op
  end
end
