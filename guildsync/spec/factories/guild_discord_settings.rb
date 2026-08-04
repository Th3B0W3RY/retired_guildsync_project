# frozen_string_literal: true

FactoryBot.define do
  factory :guild_discord_setting do
    association :guild
    sequence(:discord_guild_id) { |n| "discord_guild_#{n}" }
    discord_guild_name { "Test Discord Server" }
    bot_token { "test_bot_token" }
    connected_at { Time.current }
  end
end

