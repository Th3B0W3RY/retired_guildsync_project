# frozen_string_literal: true

FactoryBot.define do
  factory :react_role do
    association :guild
    sequence(:position) { |n| ((n - 1) % 3) + 1 }
    sequence(:role_id)  { |n| "111222333444#{n.to_s.rjust(6, "0")}" }
    role_name           { "Member Role" }
    emoji_name          { "🔥" }
    emoji_id            { nil }
    is_custom_emoji     { false }
    channel_id          { "999888777666555" }
    message_id          { nil }

    trait :custom_emoji do
      emoji_name      { "LUL" }
      emoji_id        { "41771983429993937" }
      is_custom_emoji { true }
    end

    trait :deployed do
      message_id { "777666555444333" }
    end
  end
end
