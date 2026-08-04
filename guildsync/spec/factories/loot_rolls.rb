FactoryBot.define do
  factory :loot_roll do
    title { "Test Loot Roll" }
    description { "This is a test loot roll description" }
    min_roll { 1 }
    max_roll { 100 }
    anonymous { false }
    status { :open }
    deadline_at { nil }
    association :guild
    association :creator, factory: :user

    trait :anonymous do
      anonymous { true }
    end

    trait :with_deadline do
      deadline_at { 1.week.from_now }
    end

    trait :expired do
      deadline_at { 1.hour.ago }
    end

    trait :closed do
      status { :closed }
    end

    trait :with_discord do
      discord_channel_id { "123456789" }
      discord_message_id { "987654321" }
    end

    trait :with_allowed_roles do
      allowed_role_ids { [ "111111111", "222222222" ] }
    end
  end
end
