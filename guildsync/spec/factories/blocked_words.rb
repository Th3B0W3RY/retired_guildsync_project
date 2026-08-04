# frozen_string_literal: true

FactoryBot.define do
  factory :blocked_word do
    sequence(:word) { |n| "badword#{n}" }
    category { "profanity" }
    active { true }
  end
end
