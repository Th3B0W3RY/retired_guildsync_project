# frozen_string_literal: true

FactoryBot.define do
  factory :gear_upload_request do
    association :guild
    association :requester, factory: :user
    association :target_user, factory: :user
    status { :pending }
    requested_at { Time.current }
    
    trait :completed do
      status { :completed }
      completed_at { Time.current }
    end
    
    trait :cancelled do
      status { :cancelled }
    end
  end
end

