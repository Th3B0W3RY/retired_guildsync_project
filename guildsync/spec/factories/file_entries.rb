# frozen_string_literal: true

FactoryBot.define do
  factory :file_entry do
    association :guild
    association :uploader, factory: :user
    sequence(:name) { |n| "file_#{n}.txt" }
    content_type { "text/plain" }
    size { 1024 }
    compressed { false }
    folder { nil }
    uploaded_by { |fe| fe.uploader.id }

    trait :with_file do
      after(:create) do |file_entry|
        file_entry.file.attach(
          io: StringIO.new("test file content"),
          filename: file_entry.name,
          content_type: file_entry.content_type
        )
      end
    end

    trait :image do
      name { "test_image.png" }
      content_type { "image/png" }
      size { 2048 }
      
      after(:create) do |file_entry|
        png_data = [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
          0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
          0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
          0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00,
          0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
        ].pack('C*')
        
        file_entry.file.attach(
          io: StringIO.new(png_data),
          filename: "test_image.png",
          content_type: "image/png"
        )
      end
    end
  end
end

