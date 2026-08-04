# frozen_string_literal: true

FactoryBot.define do
  factory :alliance do
    sequence(:name) { |n| "Alliance #{n}" }
    description     { "A test alliance" }
    status          { :active }
    association :leader_guild, factory: :guild
    association :leader_user,  factory: :user

    trait :disbanded do
      status { :disbanded }
    end
  end

  factory :alliance_guild do
    association :alliance
    association :guild
    status    { :active }
    joined_at { Time.current }
  end

  factory :alliance_member do
    association :alliance
    association :user
    association :guild
    role   { :member }
    status { :active }

    trait :gm do
      role { :gm }
    end

    trait :officer do
      role { :officer }
    end
  end

  factory :alliance_join_request do
    association :alliance
    association :requesting_guild, factory: :guild
    association :requested_by_user, factory: :user
    status { :pending }
  end

  factory :alliance_disband_vote do
    association :alliance
    association :user
    association :guild
    vote { true }
  end

  factory :alliance_invite do
    association :alliance
    association :guild
    association :invited_by_user, factory: :user
    status { :pending }

    trait :accepted do
      status { :accepted }
    end

    trait :declined do
      status { :declined }
    end
  end

  factory :alliance_event do
    association :alliance
    association :created_by, factory: :user
    sequence(:title) { |n| "Alliance Event #{n}" }
    description  { "A test event" }
    scheduled_at { 1.week.from_now }
    status       { :scheduled }
  end

  factory :alliance_poll do
    association :alliance
    association :creator, factory: :user
    sequence(:title) { |n| "Alliance Poll #{n}" }
    description { "A test poll" }
    deadline    { 1.week.from_now }
    anonymous   { false }
  end

  factory :alliance_loot_roll do
    association :alliance
    association :creator, factory: :user
    sequence(:title) { |n| "Alliance Roll #{n}" }
    min_roll { 1 }
    max_roll { 100 }
    anonymous { false }
    status    { :open }
  end

  factory :alliance_message do
    association :alliance
    association :sender, factory: :user
    content      { "Hello alliance!" }
    message_type { :all_members }

    trait :gm_only do
      message_type { :gm_only }
    end
  end
end
