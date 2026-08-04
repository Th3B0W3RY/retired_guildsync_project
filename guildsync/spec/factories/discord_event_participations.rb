# frozen_string_literal: true

FactoryBot.define do
  factory :discord_event_participation do
    association :event
    sequence(:discord_user_id) { |n| "discord_user_#{n}" }
    discord_username { "TestUser#1234" }
    on_time { false }
  end
end

