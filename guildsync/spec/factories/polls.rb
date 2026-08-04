FactoryBot.define do
  factory :poll do
    title { "Test Poll" }
    description { "This is a test poll description" }
    deadline { 1.week.from_now }
    anonymous { false }
    association :guild
    association :creator, factory: :user

    trait :anonymous do
      anonymous { true }
    end

    trait :closed do
      deadline { 1.day.ago }
    end

    trait :with_discord do
      discord_channel_id { "123456789" }
      discord_message_id { "987654321" }
    end

    trait :with_role_mentions do
      discord_role_mentions { ["111111111", "222222222"] }
    end
  end
end

