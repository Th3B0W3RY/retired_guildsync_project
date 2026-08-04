# frozen_string_literal: true

FactoryBot.define do
  factory :guild_member do
    association :user
    association :guild
    role { :member }
    status { :active }
  end
end

