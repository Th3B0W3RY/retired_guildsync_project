# frozen_string_literal: true

FactoryBot.define do
  factory :game do
    sequence(:name) { |n| "Test Game #{n}" }
    sequence(:slug) { |n| "test-game-#{n}" }
    description { "A test game" }
    active { true }
    ocr_config { {} }
  end
end

