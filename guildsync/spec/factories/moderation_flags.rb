# frozen_string_literal: true

FactoryBot.define do
  factory :moderation_flag do
    association :flaggable, factory: :feature_request
    status { "pending" }
  end
end
