# frozen_string_literal: true

module Games
  module RuneScape3
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # RuneScape 3 - OCR output is mostly numbers with no clear labels
          # Try to extract combat level or total level if present
          nl = BaseOcrHandler::NEWLINE
          integer = '(\d+)'
          
          extract_patterns(raw_text, data, {
            'Combat Level' => Regexp.new("combat\\s*level[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Total Level' => Regexp.new("total\\s*level[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'Item Level' => Regexp.new("item\\s*level[:\s]*#{nl}?#{integer}", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { v.to_i })
          
          # RS3 OCR is very sparse - if no data extracted, that's acceptable
          
          data
        end
      end
    end
  end
end

