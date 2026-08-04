# frozen_string_literal: true

class AllianceMessage < ApplicationRecord
  belongs_to :alliance
  belongs_to :sender, class_name: "User"

  encrypts :content, support_unencrypted_data: true

  enum :message_type, { all_members: 0, gm_only: 1 }

  validates :content,      presence: true, length: { maximum: 4000 }
  validates :alliance_id,  presence: true
  validates :sender_id,    presence: true
  validates :message_type, presence: true

  scope :recent_first,  -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }
  scope :for_all,       -> { where(message_type: :all_members) }
  scope :for_gms,       -> { where(message_type: :gm_only) }
end
