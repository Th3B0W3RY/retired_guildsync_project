# frozen_string_literal: true

module Games
  module BladeAndSoul
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # Blade & Soul - values appear on next line after label
          nl = BaseOcrHandler::NEWLINE
          integer = '(\d+)'
          
          extract_patterns(raw_text, data, {
            'Attack Power' => Regexp.new("attack\\s*power[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'HP' => Regexp.new("hp[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Defense' => Regexp.new("defense[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'PvP Attack Power' => Regexp.new("pvp\\s*attack\\s*power[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'PvP Defense' => Regexp.new("pvp\\s*defense[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Boss Attack Power' => Regexp.new("boss\\s*attack\\s*power[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Boss Defense' => Regexp.new("boss\\s*defense[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Piercing' => Regexp.new("piercing[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Accuracy' => Regexp.new("accuracy[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Critical Hit' => Regexp.new("critical\\s*hit[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Critical Def' => Regexp.new("critical\\s*def[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Critical Dmg' => Regexp.new("critical\\s*dmg[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { v.to_i })
          
          # Map Attack Power to Gear Score
          data['Gear Score'] = data['Attack Power'] if data['Attack Power']
          
          data
        end
      end
    end
  end
end

