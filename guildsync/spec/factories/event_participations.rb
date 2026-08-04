# frozen_string_literal: true

FactoryBot.define do
  factory :event_participation do
    association :event
    association :user
    status { :attending }
    notes { nil }
  end
end

