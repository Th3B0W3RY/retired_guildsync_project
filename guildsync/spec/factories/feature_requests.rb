# frozen_string_literal: true

FactoryBot.define do
  factory :feature_request do
    association :user
    sequence(:title) { |n| "Feature request #{n}" }
    description { "A clear description of the feature that is at least fifty characters long for validation." }
    status { "considering" }
  end

  factory :feature_request_comment do
    association :feature_request
    association :user
    body { "A helpful comment." }
  end
end
