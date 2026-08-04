# frozen_string_literal: true

class AllianceEventParticipation < ApplicationRecord
  belongs_to :alliance_event
  belongs_to :user, optional: true

  enum :status, { attending: 0, maybe: 1, declined: 2 }

  validates :alliance_event_id, presence: true
  validates :user_id, uniqueness: { scope: :alliance_event_id }, if: -> { user_id.present? }
  validates :discord_user_id, uniqueness: { scope: :alliance_event_id }, if: -> { discord_user_id.present? }
  validate :user_or_discord_id_present

  scope :by_discord_user, ->(did) { where(discord_user_id: did) }
  scope :by_user_or_discord, ->(user, did) { where(user_id: user&.id).or(where(discord_user_id: did)) }

  private

  def user_or_discord_id_present
    return if user_id.present? || user.present? || discord_user_id.present?
    errors.add(:base, :user_or_discord_required)
  end
end
