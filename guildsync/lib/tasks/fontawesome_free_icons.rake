# frozen_string_literal: true

# Font Awesome Free icon catalog sync.
#
# Manual tooling:
#   - fontawesome_free_icons:sync — fetch Font Awesome Free metadata into fontawesome_free_icons
#     (used by the admin icon picker and icon_key validation).
#
namespace :fontawesome_free_icons do
  desc "Download Font Awesome Free metadata and upsert icon rows (for admin picker + validation)"
  task sync: :environment do
    result = FontawesomeFreeIcons::Sync.new.call
    puts "Font Awesome Free sync: #{result[:processed]} rows from #{result[:icon_definitions]} icon definitions."
  rescue FontawesomeFreeIcons::Sync::Error => e
    warn "Font Awesome Free sync failed: #{e.message}"
    exit 1
  end
end
