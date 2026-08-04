# frozen_string_literal: true

module AccountCreation
  # Shared gate for completing account creation via an external OAuth identity
  # (Discord, Gmail, Outlook) after email verification and backup-code acknowledgment.
  class SignupGate
    def self.gated_oauth_signup_allowed?(session, user)
      return false unless user

      ActiveModel::Type::Boolean.new.cast(session[:signup_backup_confirmed]) &&
        user.backup_code_acknowledged_at.present? &&
        user.registration_completed_at.nil? &&
        user.signup_email_verified_at.present?
    end
  end
end
