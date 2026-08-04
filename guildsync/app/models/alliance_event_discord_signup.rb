# frozen_string_literal: true

class AllianceEventDiscordSignup < ApplicationRecord
  belongs_to :alliance_event

  enum :role, { dps: 0, tank: 1, healer: 2, ranged: 3 }
  enum :status, { on_time: 0, late: 1, absent: 2 }

  validates :alliance_event_id, presence: true
  validates :discord_user_id, presence: true
  validates :role, presence: true
  validates :status, presence: true
  validates :role, inclusion: { in: roles.keys }
  validates :status, inclusion: { in: statuses.keys }
  validates :discord_user_id, uniqueness: { scope: :alliance_event_id, message: :one_role_per_event }
end
