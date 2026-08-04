class LootRoll < ApplicationRecord
  include Searchable
  include SoftDeletable

  belongs_to :guild
  belongs_to :creator, class_name: "User"
  has_many :loot_roll_entries, dependent: :destroy
  belongs_to :winner_entry, class_name: "LootRollEntry", optional: true

  soft_delete_metadata display: :title, search: [ :title, :description ]

  enum :status, { open: 0, closed: 1 }

  validates :title, presence: true, length: { minimum: 1, maximum: 255 }
  validates :min_roll, :max_roll, presence: true, numericality: { greater_than: 0 }
  validate :max_greater_than_min

  scope :ordered, -> { order(created_at: :desc) }
  # Enum `open` is status-only; rolls can remain `open` until a job closes them after deadline.
  # Use this scope anywhere we mean "members can still participate" (matches #currently_open?).
  scope :open_for_participation, lambda {
    open.where("#{table_name}.deadline_at IS NULL OR #{table_name}.deadline_at > ?", Time.current)
  }

  def currently_open?
    open? && (deadline_at.nil? || deadline_at > Time.current)
  end

  def expired?
    deadline_at.present? && deadline_at <= Time.current
  end

  def determine_winner
    # Get highest roll, tie-break by Discord role position (lower = higher role)
    loot_roll_entries.where(is_reroll: false).order(roll_value: :desc, discord_role_position: :asc).first
  end

  def total_entries
    loot_roll_entries.where(is_reroll: false).count
  end

  def highest_roll
    loot_roll_entries.where(is_reroll: false).maximum(:roll_value)
  end

  def time_remaining
    return nil if deadline_at.nil?
    return 0 if deadline_at <= Time.current
    deadline_at - Time.current
  end

  def close_and_determine_winner!
    # Check for tie first
    if has_tie?
      # Don't close yet - need tiebreaker
      start_tiebreaker!
    else
      winner = determine_winner
      update!(status: :closed, winner_entry: winner, tied_discord_user_ids: nil)
    end
  end

  # Check if there's a tie for the highest roll
  def has_tie?
    return false if loot_roll_entries.active.count < 2

    highest = highest_roll
    return false if highest.nil?

    # Count how many entries have the highest roll
    loot_roll_entries.active.where(roll_value: highest).count > 1
  end

  # Get the discord user IDs of tied users
  def tied_user_ids
    return [] unless has_tie?

    highest = highest_roll
    loot_roll_entries.active.where(roll_value: highest).pluck(:discord_user_id)
  end

  # Start a tiebreaker round
  def start_tiebreaker!
    tied_ids = tied_user_ids
    return if tied_ids.empty?

    update!(
      current_tiebreaker_round: (current_tiebreaker_round || 0) + 1,
      tied_discord_user_ids: tied_ids
    )
  end

  # Check if all tied users have rerolled for the current round
  def check_tiebreaker_complete!
    return unless tied_discord_user_ids.present?

    # Get entries for tied users
    tied_entries = loot_roll_entries.active.where(discord_user_id: tied_discord_user_ids)

    # Check if all have rerolled for this round
    all_rerolled = tied_entries.all? { |e| e.tiebreaker_round >= current_tiebreaker_round }

    if all_rerolled
      # Check if there's still a tie
      if has_tie?
        # Start another tiebreaker round
        start_tiebreaker!
      else
        # We have a winner! Close the loot roll
        winner = determine_winner
        update!(status: :closed, winner_entry: winner, tied_discord_user_ids: nil)
      end
    end
  end

  # Check if we're in tiebreaker mode
  def in_tiebreaker?
    tied_discord_user_ids.present? && tied_discord_user_ids.any?
  end

  private

  def max_greater_than_min
    if min_roll.present? && max_roll.present? && max_roll <= min_roll
      errors.add(:max_roll, :must_be_greater)
    end
  end
end
