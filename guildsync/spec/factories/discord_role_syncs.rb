# frozen_string_literal: true

FactoryBot.define do
  factory :discord_role_sync do
    association :guild
    sequence(:role_id) { |n| "12345678901234567#{n}" }
    sequence(:role_name) { |n| "Role #{n}" }
  end
end

