# frozen_string_literal: true

class UserWarning < ApplicationRecord
  LEVELS = %w[warning mute_1day mute_3day mute_1week ban].freeze

  belongs_to :user
  belongs_to :issued_by, class_name: "User"

  validates :level, inclusion: { in: LEVELS }

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :for_user, ->(user_id) { where(user_id: user_id).order(created_at: :desc) }
end
