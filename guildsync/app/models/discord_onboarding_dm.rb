# frozen_string_literal: true

class DiscordOnboardingDm < ApplicationRecord
  validates :discord_user_id, presence: true
  validates :context_type, presence: true, inclusion: { in: %w[Guild Alliance] }
  validates :context_id, presence: true
  validates :sent_at, presence: true
  validates :discord_user_id, uniqueness: { scope: [:context_type, :context_id] }

  scope :for_discord_user, ->(did) { where(discord_user_id: did) }
  scope :for_context, ->(type, id) { where(context_type: type, context_id: id) }

  def self.already_sent?(discord_user_id:, context_type:, context_id:)
    exists?(discord_user_id: discord_user_id, context_type: context_type, context_id: context_id)
  end

  def self.record_sent!(discord_user_id:, context_type:, context_id:, delivered: true)
    create!(
      discord_user_id: discord_user_id,
      context_type: context_type,
      context_id: context_id,
      sent_at: Time.current,
      delivered: delivered
    )
  end
end
