# frozen_string_literal: true

FactoryBot.define do
  factory :discord_event_signup do
    association :discord_event
    sequence(:discord_user_id) { |n| "discord_user_#{n}" }
    sequence(:discord_username) { |n| "TestUser#{n}#1234" }
    role { :dps }
    status { :on_time }
  end
end
