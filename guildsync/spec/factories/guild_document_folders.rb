# frozen_string_literal: true

FactoryBot.define do
  factory :guild_document_folder do
    association :guild
    association :user
    name { "Test Folder" }
    color { "#3b82f6" }
    position { 0 }
  end
end

