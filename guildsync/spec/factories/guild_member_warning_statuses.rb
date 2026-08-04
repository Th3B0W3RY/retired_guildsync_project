# frozen_string_literal: true

FactoryBot.define do
  factory :guild_member_warning_status do
    association :guild
    association :user
    association :warned_by, factory: :user
    warning_count { 1 }
    state { :warned }
    last_warning_reason { "Repeated no-show." }
    last_warned_at { Time.current }
  end
end
