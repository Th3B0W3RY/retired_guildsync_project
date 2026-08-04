# frozen_string_literal: true

module Games
  module LostArk
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # Lost Ark - values may appear on next line after label
          nl = BaseOcrHandler::NEWLINE
          decimal = BaseOcrHandler::DECIMAL_NUMBER
          integer = '(\d+)'
          
          extract_patterns(raw_text, data, {
            'Item Level' => Regexp.new("(?:item\\s*level|ilvl)[:\s]*#{nl}?#{decimal}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Attack Power' => Regexp.new("attack\\s*(?:power|tower)[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Max HP' => Regexp.new("max\\s*hp[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Specialty' => Regexp.new("specialty[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Agility' => Regexp.new("(?:agility|aginy)[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Endurance' => Regexp.new("endurance[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Proficiency' => Regexp.new("proficiency[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { v.to_f if v && v.match?(/^\d+\.?\d*$/) })
          
          # Map item level to gear score
          data['Gear Score'] = data['Item Level'] if data['Item Level']
          
          data
        end
      end
    end
  end
end

