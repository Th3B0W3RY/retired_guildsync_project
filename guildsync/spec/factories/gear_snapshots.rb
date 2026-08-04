# frozen_string_literal: true

FactoryBot.define do
  factory :gear_snapshot do
    association :guild
    association :user
    association :game
    source { :web }
    raw_text { "Gear Score: 1642\nWeapon 1: Shadowblade +10" }
    data { { 'Gear Score' => 1642, 'Weapon 1' => 'Shadowblade +10' } }
    validation_passed { true }
    
    after(:build) do |snapshot|
      # Attach a test image if screenshot is not already attached
      unless snapshot.screenshot.attached?
        # Create a minimal valid PNG file (1x1 transparent pixel)
        png_data = [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, # PNG signature
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, # IHDR chunk
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, # 1x1 dimensions
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, # Bit depth, color type, etc.
          0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, # IDAT chunk
          0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, # Image data
          0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, # End of IDAT
          0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82  # IEND chunk
        ].pack('C*')
        
        test_image = StringIO.new(png_data)
        
        snapshot.screenshot.attach(
          io: test_image,
          filename: 'test_image.png',
          content_type: 'image/png'
        )
      end
    end
  end
end

