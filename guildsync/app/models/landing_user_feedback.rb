# frozen_string_literal: true

class LandingUserFeedback < ApplicationRecord
  include SoftDeletable

  MAX_ENTRIES = 25

  has_rich_text :body

  soft_delete_metadata display: :body_preview, search: []

  validates :body, presence: true
  validate :entry_limit_not_exceeded, on: :create

  scope :visible, -> { where(visible: true) }
  scope :ordered, -> { order(:position, :id) }

  def body_preview
    body.to_plain_text.truncate(80)
  end

  private

  def entry_limit_not_exceeded
    return if LandingUserFeedback.active.count < MAX_ENTRIES

    errors.add(:base, :entry_limit_reached, max: MAX_ENTRIES)
  end
end
