class EventParticipation < ApplicationRecord
  belongs_to :event
  belongs_to :user, optional: true

  enum :status, {
    not_attending: 0,
    maybe: 1,
    attending: 2
  }

  validates :user_id, uniqueness: { scope: :event_id, message: :already_responded }, if: -> { user_id.present? }
  validates :discord_user_id, uniqueness: { scope: :event_id, message: :already_responded }, if: -> { discord_user_id.present? }
  validate :user_or_discord_id_present

  scope :by_discord_user, ->(did) { where(discord_user_id: did) }
  scope :by_user_or_discord, ->(user, did) { where(user_id: user&.id).or(where(discord_user_id: did)) }

  private

  def user_or_discord_id_present
    return if user_id.present? || user.present? || discord_user_id.present?
    errors.add(:base, :user_or_discord_required)
  end
end
