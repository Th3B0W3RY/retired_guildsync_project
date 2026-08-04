# frozen_string_literal: true

class LootRollsChannel < ApplicationCable::Channel
  # Single payload for web close/reroll, Discord interactions, bot gateway, and deadline job.
  def self.broadcast_update(loot_roll)
    return unless loot_roll&.persisted?

    loot_roll.reload
    mask_names = loot_roll.anonymous?
    entries = loot_roll.loot_roll_entries.active.ordered_by_roll.map do |entry|
      {
        id:           entry.id,
        display_name: mask_names ? "Anonymous" : entry.display_name,
        roll_value:   entry.roll_value,
        is_winner:    entry.id == loot_roll.winner_entry_id
      }
    end

    broadcast_to(loot_roll, {
      type:             "loot_roll_update",
      entries:          entries,
      total_entries:    loot_roll.total_entries,
      status:           loot_roll.status,
      currently_open:   loot_roll.currently_open?,
      winner_id:        loot_roll.winner_entry_id,
      has_tie:          loot_roll.has_tie?
    })
  end

  def subscribed
    loot_roll_id = params[:loot_roll_id].to_i
    if loot_roll_id <= 0
      reject
      return
    end

    loot_roll = LootRoll.find_by(id: loot_roll_id)
    unless loot_roll
      reject
      return
    end

    guild = loot_roll.guild
    unless current_user && (guild.members.include?(current_user) || guild.owner == current_user)
      reject
      return
    end

    stream_for loot_roll
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
