# frozen_string_literal: true

FactoryBot.define do
  factory :subscription do
    association :user
    association :pricing_plan
    status { :active }
    started_at { Time.current }
    expires_at { nil }
  end
end

