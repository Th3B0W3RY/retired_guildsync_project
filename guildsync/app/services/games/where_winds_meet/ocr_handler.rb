# frozen_string_literal: true

module Games
  module WhereWindsMeet
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # Where Winds Meet - values appear on next line after label
          nl = BaseOcrHandler::NEWLINE
          integer = '(\d+)'
          thousands = BaseOcrHandler::THOUSANDS_NUMBER
          
          extract_patterns(raw_text, data, {
            'Gear Score' => Regexp.new("gear\\s*score[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Item Level' => Regexp.new("item\\s*level[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Max HP' => Regexp.new("max\\s*hp[:\s]*#{nl}?#{thousands}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Physical Attack' => Regexp.new("physical\\s*attack[:\s]*#{nl}?(\\d+-\\d+)", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Physical Defense' => Regexp.new("physical\\s*defense[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Body' => Regexp.new("body[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Power' => Regexp.new("power[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Defense' => Regexp.new("defense[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Agility' => Regexp.new("agility[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Momentum' => Regexp.new("momentum[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { v.gsub(',', '').to_i })
          
          data
        end
      end
    end
  end
end

