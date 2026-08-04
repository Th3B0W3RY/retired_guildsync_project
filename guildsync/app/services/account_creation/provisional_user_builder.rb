# frozen_string_literal: true

module AccountCreation
  class ProvisionalUserBuilder
    def self.call(email:, ip_address:)
      new(email: email, ip_address: ip_address).call
    end

    def initialize(email:, ip_address:)
      @email = SignupEmailVerification.normalize_email(email)
      @ip_address = ip_address
    end

    def call
      user = User.find_by(email: email)
      return user if user&.pending_registration?

      raise ActiveRecord::RecordInvalid.new(user) if user

      User.create!(
        email: email,
        username: provisional_username,
        password: "A#{SecureRandom.hex(32)}1",
        signup_ip: ip_address,
        signup_email_verified_at: Time.current,
        confirmed_at: Time.current,
        registration_completed_at: nil,
        provisional_registration: true
      )
    end

    private

    attr_reader :email, :ip_address

    def provisional_username
      loop do
        username = "pending_#{SecureRandom.hex(6)}"
        return username unless User.exists?(username: username)
      end
    end
  end
end
