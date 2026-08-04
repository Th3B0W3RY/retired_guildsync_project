# frozen_string_literal: true

FactoryBot.define do
  factory :landing_user_feedback do
    visible { true }
    sequence(:position)

    after(:build) do |record|
      record.body = "<p>GuildSync testimonial #{record.position}</p>"
    end

    trait :soft_deleted do
      deleted_at { Time.current }
    end
  end

  factory :fontawesome_free_icon do
    style { "solid" }
    sequence(:icon_name) { |n| "icon-#{n}" }
    sequence(:label) { |n| "Icon #{n}" }
  end

  factory :homepage_feature_card do
    sequence(:slug) { |n| "test_feature_#{n}" }
    sequence(:title) { |n| "Test Feature #{n}" }
    description { "Short marketing description for the card." }
    icon_key { "member_management" }
    visible { true }
    sequence(:position)

    trait :soft_deleted do
      deleted_at { Time.current }
    end
  end
end
