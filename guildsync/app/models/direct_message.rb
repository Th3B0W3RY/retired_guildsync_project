# frozen_string_literal: true

class DirectMessage < ApplicationRecord
  belongs_to :sender, class_name: "User"
  belongs_to :recipient, class_name: "User"
  belongs_to :guild, optional: true

  encrypts :content, support_unencrypted_data: true

  validates :content, presence: true, length: { maximum: 4000 }

  scope :between, ->(user_a, user_b) {
    where(sender_id: [ user_a.id, user_b.id ], recipient_id: [ user_a.id, user_b.id ])
      .where("(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)", user_a.id, user_b.id, user_b.id, user_a.id)
  }
  scope :recent_first, -> { order(created_at: :desc) }
end
