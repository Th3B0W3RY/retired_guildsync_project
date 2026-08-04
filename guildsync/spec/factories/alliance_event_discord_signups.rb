# frozen_string_literal: true

FactoryBot.define do
  factory :alliance_event_discord_signup do
    association :alliance_event
    sequence(:discord_user_id) { |n| "alliance_discord_user_#{n}" }
    sequence(:discord_username) { |n| "AllianceUser#{n}#0001" }
    sequence(:discord_display_name) { |n| "Alliance User #{n}" }
    role { :dps }
    status { :on_time }
  end
end
