class UserComplianceWarning < ApplicationRecord
  WARNING_TYPE_IP_CONFLICT = "ip_multi_account_guild_conflict"

  belongs_to :user

  validates :warning_type, presence: true
  validates :message, presence: true

  scope :active, -> { where(active: true) }
  scope :for_type, ->(type) { where(warning_type: type) }
end
