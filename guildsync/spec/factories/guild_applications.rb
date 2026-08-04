# frozen_string_literal: true

FactoryBot.define do
  factory :guild_application do
    association :user
    association :guild
    discord_username { Faker::Internet.username(specifier: 5..10) + "##{Faker::Number.between(from: 1000, to: 9999)}" }
    message { "I would like to join this guild" }
    status { "pending" }
  end
end

