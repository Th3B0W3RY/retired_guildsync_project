# frozen_string_literal: true

FactoryBot.define do
  factory :error_log do
    error_class { "StandardError" }
    message { "Test error message" }
    occurred_at { 1.hour.ago }
    backtrace { "backtrace line 1\nbacktrace line 2" }
    context { {} }

    trait :resolved do
      resolved_at { 30.minutes.ago }
      resolved_by { "admin@test.com" }
    end
  end
end

