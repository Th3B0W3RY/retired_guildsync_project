# frozen_string_literal: true

module AccountCreation
  class SignupSession
    KEYS = [
      :signup_verification_id,
      :signup_user_id,
      :signup_backup_code,
      :signup_backup_confirmed,
      :signup_method
    ].freeze

    def self.clear!(session)
      KEYS.each { |key| session.delete(key) }
    end
  end
end
