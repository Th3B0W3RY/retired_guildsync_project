# frozen_string_literal: true

FactoryBot.define do
  factory :user_recent_activity do
    association :user
    path { "/dashboard" }
    label { "Viewed Dashboard" }
  end
end
