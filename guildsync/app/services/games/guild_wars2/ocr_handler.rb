# frozen_string_literal: true

module Games
  module GuildWars2
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # Guild Wars 2 - OCR text is noisy, try to extract Level and any numeric attributes
          nl = BaseOcrHandler::NEWLINE
          integer = '(\d+)'
          thousands = BaseOcrHandler::THOUSANDS_NUMBER
          
          extract_patterns(raw_text, data, {
            'Level' => Regexp.new("level\\s+#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Item Level' => Regexp.new("item\\s*level[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Gear Score' => Regexp.new("gear\\s*score[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Power' => Regexp.new("power[:\s]*#{nl}?#{thousands}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Precision' => Regexp.new("precision[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Toughness' => Regexp.new("toughness[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Vitality' => Regexp.new("vitality[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { v.gsub(',', '').to_i })
          
          data
        end
      end
    end
  end
end

