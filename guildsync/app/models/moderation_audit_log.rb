# frozen_string_literal: true

class ModerationAuditLog < ApplicationRecord

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_content, ->(type, id) { where(content_type: type, content_id: id) }

  def self.log!(admin_email:, action:, content_type: nil, content_id: nil, notes: nil, admin_id: nil)
    create!(
      admin_email: admin_email,
      admin_id: admin_id,
      action: action,
      content_type: content_type,
      content_id: content_id,
      notes: notes
    )
  end
end
