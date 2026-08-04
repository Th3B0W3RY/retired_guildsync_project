class DiscordEventSignup < ApplicationRecord
  belongs_to :discord_event

  enum :role, { dps: 0, tank: 1, healer: 2, ranged: 3 }
  enum :status, { on_time: 0, late: 1, absent: 2 }

  validates :discord_user_id, presence: true
  validates :discord_event_id, presence: true
  validates :role, presence: true
  validates :status, presence: true
  validates :role, inclusion: { in: %w[dps tank healer ranged] }
  validates :status, inclusion: { in: %w[on_time late absent] }
  # Enforce ONE signup per user per event (not per role)
  validates :discord_user_id, uniqueness: { scope: :discord_event_id, message: :one_role_per_event }
end

