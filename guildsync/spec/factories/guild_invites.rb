# frozen_string_literal: true

FactoryBot.define do
  factory :guild_invite do
    association :user
    association :guild
    association :invited_by, factory: :user
    status { :pending }
  end
end

