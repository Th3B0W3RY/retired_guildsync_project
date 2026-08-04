# frozen_string_literal: true

FactoryBot.define do
  factory :profanity_update_log do
    timestamp { Time.current }
    sources_checked { [] }
    new_words_added { 0 }
    words_removed { 0 }
    total_words { 100 }
    error_messages { [] }
  end
end
