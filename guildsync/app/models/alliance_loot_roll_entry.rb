# frozen_string_literal: true

class AllianceLootRollEntry < ApplicationRecord
  belongs_to :alliance_loot_roll
  belongs_to :user, optional: true

  validates :alliance_loot_roll_id, presence: true
  validates :user_id, uniqueness: { scope: :alliance_loot_roll_id, message: "has already entered this roll" }, if: -> { user_id.present? }
  validates :discord_user_id, uniqueness: { scope: :alliance_loot_roll_id, message: "has already entered this roll" }, if: -> { discord_user_id.present? }
  validate :user_or_discord_id_present

  before_create :set_display_name
  before_create :generate_roll

  def display_name
    self[:display_name] || user&.display_name
  end

  private

  def set_display_name
    self.display_name ||= user&.name_for_discord_embed || discord_username || "Unknown"
  end

  def generate_roll
    return if roll_value.present?
    self.roll_value = rand(alliance_loot_roll.min_roll..alliance_loot_roll.max_roll)
  end

  def user_or_discord_id_present
    return if user_id.present? || user.present? || discord_user_id.present?
    errors.add(:base, :user_or_discord_required)
  end
end
