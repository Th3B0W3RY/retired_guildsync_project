# frozen_string_literal: true

FactoryBot.define do
  factory :user_discord_connection do
    association :user
    sequence(:discord_user_id) { |n| "discord_user_#{n}" }
    access_token { "access_#{SecureRandom.hex(8)}" }
    refresh_token { "refresh_#{SecureRandom.hex(8)}" }
    expires_at { 1.hour.from_now }
  end
end
