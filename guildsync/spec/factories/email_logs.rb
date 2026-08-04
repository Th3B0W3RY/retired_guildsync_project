# frozen_string_literal: true

FactoryBot.define do
  factory :email_log do
    sequence(:to) { |n| "user#{n}@test.com" }
    subject { "Test Email" }
    status { "sent" }
    sent_at { 1.hour.ago }
    retry_count { 0 }

    trait :failed do
      status { "failed" }
      error_message { "SMTP error" }
      sent_at { nil }
    end

    trait :pending do
      status { "pending" }
      sent_at { nil }
    end
  end
end

