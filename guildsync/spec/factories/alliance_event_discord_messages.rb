# frozen_string_literal: true

FactoryBot.define do
  factory :alliance_event_discord_message do
    association :alliance_event
    association :guild
    sequence(:channel_id) { |n| "alliance_channel_#{n}" }
    sequence(:discord_message_id) { |n| "alliance_message_#{n}" }
    posted_at { Time.current }
  end
end
