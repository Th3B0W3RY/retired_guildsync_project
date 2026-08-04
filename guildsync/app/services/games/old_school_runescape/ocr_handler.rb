# frozen_string_literal: true

module Games
  module OldSchoolRuneScape
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # Old School RuneScape - values appear after colon on same line
          # Format: "Stab: +43" or "Magic: -50<br>Range: +13"
          # Note: Raw text may contain HTML <br> tags that need to be handled
          integer = '(\d+)'
          signed_integer = '([+-]?\\d+)'
          
          # Extract attack bonuses (appear before defense bonuses)
          # Pattern: "Stab: +43" - match the stat name, colon, optional space, sign, number
          if raw_text.match(/attack\s*bonus/i)
            attack_section = raw_text.split(/defence\s*bonus/i).first
            extract_patterns(attack_section, data, {
              'Stab Attack' => Regexp.new("\\bstab[:\s]+\\+#{integer}(?=<|\\n|\\brange|$)", Regexp::IGNORECASE | Regexp::MULTILINE),
              'Slash Attack' => Regexp.new("\\bslash[:\s]+\\+#{integer}(?=<|\\n|$)", Regexp::IGNORECASE | Regexp::MULTILINE),
              'Crush Attack' => Regexp.new("\\bcrush[:\s]+\\+#{integer}(?=<|\\n|$)", Regexp::IGNORECASE | Regexp::MULTILINE),
              'Magic Attack' => Regexp.new("\\bmagic[:\s]+#{signed_integer}(?=<|\\n|\\brange|$)", Regexp::IGNORECASE | Regexp::MULTILINE),
              'Range Attack' => Regexp.new("\\brange[:\s]+\\+#{integer}(?=<|\\n|$)", Regexp::IGNORECASE | Regexp::MULTILINE)
            }, match_index: 1, transform: ->(v) { v.to_i })
          end
          
          # Extract defense bonuses
          # Pattern: "Stab: +238" - same format as attack
          if raw_text.match(/defence\s*bonus/i)
            defense_section = raw_text.split(/defence\s*bonus/i).last
            defense_section = defense_section.split(/other\s*bonuses/i).first if defense_section.match(/other\s*bonuses/i)
            extract_patterns(defense_section, data, {
              'Stab Defense' => Regexp.new("\\bstab[:\s]+\\+#{integer}(?=<|\\n|$)", Regexp::IGNORECASE | Regexp::MULTILINE),
              'Slash Defense' => Regexp.new("\\bslash[:\s]+\\+#{integer}(?=<|\\n|$)", Regexp::IGNORECASE | Regexp::MULTILINE),
              'Crush Defense' => Regexp.new("\\b(?:crosh|crush)[:\s]+\\+#{integer}(?=<|\\n|$)", Regexp::IGNORECASE | Regexp::MULTILINE),
              'Magic Defense' => Regexp.new("\\bmagic[:\s]+#{signed_integer}(?=<|\\n|$)", Regexp::IGNORECASE | Regexp::MULTILINE),
              'Range Defense' => Regexp.new("\\brange[:\s]+\\+#{integer}(?=<|\\n|$)", Regexp::IGNORECASE | Regexp::MULTILINE)
            }, match_index: 1, transform: ->(v) { v.to_i })
          end
          
          # Extract other bonuses
          # Pattern: "Strength: +132" - stop at <br> or newline before next stat
          if raw_text.match(/other\s*bonuses/i)
            other_section = raw_text.split(/other\s*bonuses/i).last
            extract_patterns(other_section, data, {
              'Strength Bonus' => Regexp.new("\\bstrength[:\s]+\\+#{integer}(?=<|\\n|\\bprayer|$)", Regexp::IGNORECASE | Regexp::MULTILINE),
              'Prayer Bonus' => Regexp.new("\\bprayer[:\s]+\\+#{integer}(?=<|\\n|$)", Regexp::IGNORECASE | Regexp::MULTILINE)
            }, match_index: 1, transform: ->(v) { v.to_i })
          end
          
          data
        end
      end
    end
  end
end

