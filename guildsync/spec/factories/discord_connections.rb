# frozen_string_literal: true

FactoryBot.define do
  factory :discord_connection do
    association :guild
    association :user
    sequence(:discord_user_id) { |n| "discord_user_#{n}" }
    sequence(:discord_username) { |n| "DiscordUser#{n}#1234" }
    access_token { "fake_access_token_#{SecureRandom.hex(16)}" }
    refresh_token { "fake_refresh_token_#{SecureRandom.hex(16)}" }
    expires_at { 1.hour.from_now }
  end
end

