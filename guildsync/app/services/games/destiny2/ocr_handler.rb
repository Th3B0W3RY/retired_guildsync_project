# frozen_string_literal: true

module Games
  module Destiny2
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # Destiny 2 - values may appear on next line after label
          nl = BaseOcrHandler::NEWLINE
          integer = '(\d+)'
          
          extract_patterns(raw_text, data, {
            'Power Level' => Regexp.new("(?:<b>POWER</b>|power\\s*level)[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Power' => Regexp.new("power[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { v.to_i })
          
          # Map Power Level to Gear Score for consistency
          data['Gear Score'] = data['Power Level'] || data['Power']
          
          data
        end
      end
    end
  end
end

