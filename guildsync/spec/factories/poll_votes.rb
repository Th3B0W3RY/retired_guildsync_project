FactoryBot.define do
  factory :poll_vote do
    association :poll
    association :user
    choice { :yes }

    trait :yes do
      choice { :yes }
    end

    trait :no do
      choice { :no }
    end

    trait :maybe do
      choice { :maybe }
    end
  end
end

