class LootRollEntry < ApplicationRecord
  belongs_to :loot_roll

  validates :discord_user_id, presence: true
  validates :display_name, presence: true
  validates :roll_value, presence: true
  validates :discord_user_id, uniqueness: {
    scope: :loot_roll_id,
    message: :already_rolled,
    conditions: -> { where(is_reroll: false) }
  }
  validate :roll_within_bounds
  validate :loot_roll_is_open, on: :create

  scope :active, -> { where(is_reroll: false) }
  scope :ordered_by_roll, -> { order(roll_value: :desc, discord_role_position: :asc) }

  def winner?
    loot_roll.winner_entry_id == id
  end

  private

  def roll_within_bounds
    return unless loot_roll && roll_value
    unless roll_value.between?(loot_roll.min_roll, loot_roll.max_roll)
      errors.add(:roll_value, :out_of_bounds, min: loot_roll.min_roll, max: loot_roll.max_roll)
    end
  end

  def loot_roll_is_open
    return unless loot_roll
    unless loot_roll.currently_open?
      errors.add(:base, :loot_roll_closed)
    end
  end
end
