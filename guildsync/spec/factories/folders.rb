# frozen_string_literal: true

FactoryBot.define do
  factory :folder do
    association :guild
    sequence(:name) { |n| "Folder #{n}" }
    parent_folder { nil }
  end
end

