# frozen_string_literal: true

FactoryBot.define do
  factory :event do
    association :guild
    association :created_by, factory: :user
    sequence(:title) { |n| "Event #{n}" }
    description { "A test event" }
    scheduled_at { 1.hour.from_now }
    duration { 60 }
    status { :scheduled }
  end
end

