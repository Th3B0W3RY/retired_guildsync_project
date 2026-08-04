# frozen_string_literal: true

FactoryBot.define do
  factory :login_history do
    association :user
    ip_address { "127.0.0.1" }
    user_agent { "Test Agent" }
    login_at { 1.hour.ago }

    trait :active do
      logout_at { nil }
    end

    trait :closed do
      logout_at { 30.minutes.ago }
    end
  end
end

