# frozen_string_literal: true

class BackupCode < ApplicationRecord
  belongs_to :user

  scope :active, -> { where(active: true, used: false) }
  scope :used, -> { where(used: true) }
  scope :invalidated, -> { where(active: false) }

  def self.valid_for_user?(user, submitted_code, request: nil)
    normalized = submitted_code.to_s.gsub(/[-\s]/, "").upcase
    return false if normalized.blank? || normalized.length != 24

    user.backup_codes.active.find_each do |stored_code|
      if BCrypt::Password.new(stored_code.code_digest).is_password?(normalized)
        stored_code.update!(
          used: true,
          used_at: Time.current,
          active: false
        )
        BackupCodeUsageLog.create!(
          user: user,
          backup_code_id: stored_code.id,
          used_at: Time.current,
          ip_address: request&.remote_ip,
          user_agent: request&.user_agent
        )
        return true
      end
    end
    false
  end
end
