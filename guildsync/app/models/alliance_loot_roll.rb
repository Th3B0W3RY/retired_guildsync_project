# frozen_string_literal: true

class AllianceLootRoll < ApplicationRecord
  include SoftDeletable

  belongs_to :alliance
  belongs_to :creator, class_name: "User"
  belongs_to :winner_entry, class_name: "AllianceLootRollEntry", optional: true
  has_many   :alliance_loot_roll_entries, dependent: :destroy
  has_many   :alliance_loot_roll_discord_messages, dependent: :delete_all

  soft_delete_metadata display: :title, search: [ :title, :description ]

  set_callback :soft_delete, :before, :purge_discord_messages

  def purge_discord_messages
    DiscordAllianceLootRollService.delete_all_linked_messages(self)
  rescue StandardError => e
    Rails.logger.warn "[AllianceLootRoll] purge_discord_messages roll=#{id}: #{e.class}: #{e.message}"
  end

  enum :status, { open: 0, closed: 1 }

  validates :title,    presence: true, length: { minimum: 1, maximum: 255 }
  validates :min_roll, :max_roll, presence: true, numericality: { greater_than: 0 }
  validate  :max_greater_than_min

  scope :ordered, -> { order(created_at: :desc) }

  def currently_open?
    open? && (deadline_at.nil? || deadline_at > Time.current)
  end

  def expired?
    deadline_at.present? && deadline_at <= Time.current
  end

  def highest_roll
    alliance_loot_roll_entries.maximum(:roll_value)
  end

  def total_entries
    alliance_loot_roll_entries.count
  end

  def close_and_determine_winner!
    winner = alliance_loot_roll_entries.order(roll_value: :desc).first
    update!(status: :closed, winner_entry: winner)
  end

  private

  def max_greater_than_min
    return unless min_roll.present? && max_roll.present? && max_roll <= min_roll
    errors.add(:max_roll, "must be greater than minimum roll")
  end
end
