# frozen_string_literal: true

module Games
  module AshesOfCreation
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # Ashes of Creation specific parsing - extract attributes and stats
          # Note: In OCR output, values appear on the line AFTER the label
          # Using multiline matching to handle values on next line
          nl = BaseOcrHandler::NEWLINE
          thousands = BaseOcrHandler::THOUSANDS_NUMBER
          decimal = BaseOcrHandler::DECIMAL_NUMBER
          percent = BaseOcrHandler::PERCENTAGE
          
          extract_patterns(raw_text, data, {
            'Level' => /level\s+(\d+)/im,
            'Strength' => Regexp.new("strength#{nl}#{thousands}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Intelligence' => Regexp.new("intelligence#{nl}#{thousands}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Dexterity' => Regexp.new("(?:dexterity|dextenty)#{nl}#{thousands}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Wisdom' => Regexp.new("wisdom#{nl}#{thousands}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Constitution' => Regexp.new("constitution#{nl}#{thousands}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Mentality' => Regexp.new("mentality#{nl}#{thousands}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Phys Power' => Regexp.new("phys\\s*power#{nl}#{decimal}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Phys Defense' => Regexp.new("phys\\s*defense#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Mag Power' => Regexp.new("mag\\s*power#{nl}#{decimal}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Mag Defense' => Regexp.new("mag\\s*defense#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { v.gsub(',', '').to_f })
          
          data
        end
      end
    end
  end
end

