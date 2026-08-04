class PollVote < ApplicationRecord
  belongs_to :poll
  belongs_to :user, optional: true

  enum :choice, { yes: 0, no: 1, maybe: 2 }

  validates :choice, presence: true
  validates :user_id, uniqueness: { scope: :poll_id, message: :one_vote_only }, if: -> { user_id.present? }
  validates :discord_user_id, uniqueness: { scope: :poll_id, message: :one_vote_only }, if: -> { discord_user_id.present? }
  validate :user_or_discord_id_present

  scope :by_discord_user, ->(did) { where(discord_user_id: did) }
  scope :by_user_or_discord, ->(user, did) { where(user_id: user&.id).or(where(discord_user_id: did)) }

  private

  def user_or_discord_id_present
    return if user_id.present? || user.present? || discord_user_id.present?
    errors.add(:base, :user_or_discord_required)
  end
end
