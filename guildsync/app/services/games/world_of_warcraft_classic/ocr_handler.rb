# frozen_string_literal: true

module Games
  module WorldOfWarcraftClassic
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # World of Warcraft Classic - values appear on next line after label
          nl = BaseOcrHandler::NEWLINE
          integer = '(\d+)'
          
          extract_patterns(raw_text, data, {
            'Level' => /level\s+(\d+)/im,
            'Strength' => Regexp.new("strength[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Agility' => Regexp.new("agility[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Stamina' => Regexp.new("stamina[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Intellect' => Regexp.new("intellect[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Spirit' => Regexp.new("spirit[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Armor' => Regexp.new("armor[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Item Level' => Regexp.new("item\\s*level[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { v.to_i if v && v.match?(/^\d+$/) })
          
          # Map item level to gear score if present
          data['Gear Score'] = data['Item Level'] if data['Item Level'] && !data['Gear Score']
          
          data
        end
      end
    end
  end
end

