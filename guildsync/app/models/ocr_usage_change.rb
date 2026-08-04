# frozen_string_literal: true

class OcrUsageChange < ApplicationRecord
  belongs_to :user

  validates :delta, :reason, :admin_email, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
end
