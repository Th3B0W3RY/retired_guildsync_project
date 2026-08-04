# frozen_string_literal: true

# Configure Zeitwerk autoloader to handle special naming conventions
Rails.autoloaders.each do |autoloader|
  # Inflect folder names to match actual module names
  autoloader.inflector.inflect(
    # Game handler folders with special casing
    "old_school_runescape" => "OldSchoolRuneScape",
    "runescape3" => "RuneScape3"
  )
end
