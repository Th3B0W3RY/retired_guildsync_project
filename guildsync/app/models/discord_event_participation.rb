class DiscordEventParticipation < ApplicationRecord
  belongs_to :event

  validates :discord_user_id, presence: true
  validates :discord_username, presence: true
  validates :discord_user_id, uniqueness: { scope: :event_id, message: :already_signed_up }
end
