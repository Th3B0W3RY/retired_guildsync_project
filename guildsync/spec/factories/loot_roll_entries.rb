FactoryBot.define do
  factory :loot_roll_entry do
    sequence(:discord_user_id) { |n| "discord_user_#{n}" }
    display_name { "Test User" }
    roll_value { rand(1..100) }
    discord_role_position { nil }
    is_reroll { false }
    association :loot_roll

    trait :high_roll do
      roll_value { 95 }
    end

    trait :low_roll do
      roll_value { 5 }
    end

    trait :with_role_position do
      discord_role_position { 5 }
    end

    trait :high_rank do
      discord_role_position { 1 }
    end

    trait :low_rank do
      discord_role_position { 10 }
    end

    trait :reroll do
      is_reroll { true }
    end
  end
end
