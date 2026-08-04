# frozen_string_literal: true

module Games
  module WorldOfWarcraft
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          normalized_text = raw_text.to_s
            .gsub(/\b5trength\b/i, "strength")
            .gsub(/\bstength\b/i, "strength")
            .gsub(/\bstrengh\b/i, "strength")
          
          # World of Warcraft - values appear on next line after label
          nl = BaseOcrHandler::NEWLINE
          integer = '(\d+)'
          
          extract_patterns(normalized_text, data, {
            'Level' => /level\s+(\d+)/im,
            'Strength' => Regexp.new("(?:strength|stength|strengh|5trength)\\s*:?\\s*(?:\\[[^\\n]*\\][^\\n]*\\s*)?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Agility' => Regexp.new("agility[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Stamina' => Regexp.new("stamina[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Intellect' => Regexp.new("intellect[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Spirit' => Regexp.new("spirit[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Armor' => Regexp.new("armor[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Melee Attack' => Regexp.new("melee\\s+attack[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Damage' => Regexp.new("damage[:\s]*#{nl}?(\\d+(?:-\\d+)?)", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Item Level' => Regexp.new("item\\s*level[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Gear Score' => Regexp.new("gear\\s*score[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { v.to_i if v && v.match?(/^\d+$/) })
          
          # Map item level to gear score if present
          data['Gear Score'] = data['Item Level'] if data['Item Level'] && !data['Gear Score']
          
          data
        end
      end
    end
  end
end

