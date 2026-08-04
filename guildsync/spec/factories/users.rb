# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { "u#{SecureRandom.hex(10)}@example.com" }
    username { "u#{SecureRandom.hex(10)}" }
    password { "password123" }
    password_confirmation { "password123" }
    confirmed_at { Time.current }
    signup_email_verified_at { Time.current }

    trait :confirmed do
      confirmed_at { Time.current }
    end

    trait :unconfirmed do
      confirmed_at { nil }
    end

    # MFA fields (optional, can be enabled later)
    otp_secret { nil }
    mfa_enabled { false }
    mfa_verified { false }

    trait :with_mfa do
      otp_secret { ROTP::Base32.random }
      mfa_enabled { true }
      mfa_verified { true }
    end

    # Default auth_method is :mfa, which requires MFA setup in ApplicationController.
    # Use this trait in request specs that are not testing the MFA flow.
    trait :discord_auth do
      auth_method { :discord }
    end
  end
end
