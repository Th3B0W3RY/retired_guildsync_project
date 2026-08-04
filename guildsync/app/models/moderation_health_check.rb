# frozen_string_literal: true

class ModerationHealthCheck < ApplicationRecord
  validates :check_id, presence: true

  scope :recent, -> { order(created_at: :desc).limit(10) }
  scope :failing, -> { where(passed: false) }
  scope :last_24_hours, -> { where("created_at > ?", 24.hours.ago) }

  def self.last_health_status
    recent.first
  end

  def self.health_score
    checks = last_24_hours
    return 100 if checks.empty?

    pass_count = checks.where(passed: true).count
    (pass_count.to_f / checks.count * 100).round
  end
end
