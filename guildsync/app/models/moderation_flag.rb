# frozen_string_literal: true

class ModerationFlag < ApplicationRecord
  belongs_to :flaggable, polymorphic: true, optional: true
  belongs_to :reported_by, class_name: "User", optional: true

  validates :status, inclusion: { in: %w[pending resolved dismissed] }

  scope :pending, -> { where(status: "pending") }
end
