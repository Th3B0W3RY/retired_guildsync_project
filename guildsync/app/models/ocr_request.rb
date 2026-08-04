# frozen_string_literal: true

class OcrRequest < ApplicationRecord
  belongs_to :user
  belongs_to :initiated_by, class_name: "User", optional: true

  validates :user_id, presence: true

  scope :for_month, ->(date = Time.current) {
    where(created_at: date.beginning_of_month..date.end_of_month)
  }

  after_create :check_abuse_patterns

  private

  def check_abuse_patterns
    actor_id = initiated_by_id.presence || user_id
    recent_count = OcrRequest
      .where("COALESCE(initiated_by_id, user_id) = ?", actor_id)
      .where("created_at > ?", 1.minute.ago)
      .count
    return unless recent_count > 50

    AbuseFlag.find_or_create_by(
      target_type: "User",
      target_value: actor_id.to_s,
      reason: "Rapid OCR requests: #{recent_count} in 1 minute",
      severity: 3
    )
  end
end
