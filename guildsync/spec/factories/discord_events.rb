# frozen_string_literal: true

FactoryBot.define do
  factory :discord_event do
    association :guild
    association :discord_connection
    sequence(:discord_event_id) { |n| "discord_event_#{n}" }
    sequence(:discord_message_id) { |n| "discord_message_#{n}" }
    sequence(:channel_id) { |n| "channel_#{n}" }
    title { "Test Event" }
    description { "This is a test event" }
    scheduled_at { 1.day.from_now }
    event_type { "pvp" }
  end
end
