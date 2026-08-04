# frozen_string_literal: true

FactoryBot.define do
  factory :guild_document do
    association :guild
    association :user
    title { Faker::Lorem.sentence(word_count: 3) }
    visibility { :private_doc }
    content { { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "Sample document content" }] }] } }
    slug { "#{title.parameterize}-#{SecureRandom.hex(4)}" }
  end

  trait :public do
    visibility { :public_doc }
  end

  trait :unlisted do
    visibility { :unlisted_doc }
  end
end
