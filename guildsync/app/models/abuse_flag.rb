# frozen_string_literal: true

class AbuseFlag < ApplicationRecord
  validates :target_type, :target_value, :reason, presence: true
  validates :severity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_target, ->(type, value) { where(target_type: type, target_value: value.to_s) }
  scope :recent, -> { where("created_at > ?", 7.days.ago) }
end
