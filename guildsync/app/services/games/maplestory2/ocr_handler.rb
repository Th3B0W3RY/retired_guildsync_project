# frozen_string_literal: true

module Games
  module Maplestory2
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          normalized_text = raw_text.to_s
            .gsub(/\b5tr\b/i, "str")
            .gsub(/\bstf\b/i, "str")
            .gsub(/\bsir\b/i, "str")
          
          # MapleStory 2 - values appear on next line after label
          # Handle HTML tags in OCR output (e.g., <b>Combat Power</b>)
          nl = BaseOcrHandler::NEWLINE
          value_prefix = '(?:[-+−•·]\s*)?'
          thousands = "#{value_prefix}([\\d,\\s]+)"
          decimal = BaseOcrHandler::DECIMAL_NUMBER
          percent = "#{value_prefix}([\\d.]+(?:%)?)"
          integer = '(\d+)'
          millions = "#{value_prefix}([\\d,\\s]+)"  # For millions (same as thousands but context matters)
          
          # Combat Power (int with commas, millions potential)
          # Pattern: "<b>Combat Power</b>\n7,886,120" - handle HTML tags
          if combat_power_match = normalized_text.match(/combat\s*power[<>\/b\s]*\s*\n\s*([-\+−•·\d,\s]+)/i)
            parsed = parse_numeric_value(combat_power_match[1])
            data['Combat Power'] = parsed.to_i if parsed
          end
          
          # Main stats (all int with thousands potential)
          # Pattern: "HP\n68,734" or "STR (*)\n2.694" (OCR may misread comma as period)
          if hp_match = normalized_text.match(/\bhp\b\s*\n\s*([\d,.]+)/i)
            val = hp_match[1].gsub(/\.(\d{3})$/, ',\1').gsub(',', '').to_i
            data['HP'] = val
          end
          
          if mp_match = normalized_text.match(/\bmp\b\s*\n\s*([\d,.]+)/i)
            val = mp_match[1].gsub(/\.(\d{3})$/, ',\1').gsub(',', '').to_i
            data['MP'] = val
          end
          
          if str_match = normalized_text.match(/(?:\bstr\b|strength)[^\n]*\s*(?:\n|\s+)\s*([\d,.]+)/i)
            val = str_match[1].gsub(/\.(\d{3})$/, ',\1').gsub(',', '').to_i
            data['STR'] = val
          end
          
          if dex_match = normalized_text.match(/\bdex\b[^\n]*\s*\n\s*([\d,.]+)/i)
            val = dex_match[1].gsub(/\.(\d{3})$/, ',\1').gsub(',', '').to_i
            data['DEX'] = val
          end
          
          if int_match = normalized_text.match(/\bint\b[^\n]*\s*\n\s*([\d,.]+)/i)
            val = int_match[1].gsub(/\.(\d{3})$/, ',\1').gsub(',', '').to_i
            data['INT'] = val
          end
          
          if luk_match = normalized_text.match(/\bluk\b[^\n]*\s*\n\s*([\d,.]+)/i)
            val = luk_match[1].gsub(/\.(\d{3})$/, ',\1').gsub(',', '').to_i
            data['LUK'] = val
          end

          # Fallback for OCR ordering noise: allow nearby numeric lines around stat labels.
          lines = normalized_text.split("\n").map(&:strip).reject(&:empty?)
          data['STR'] ||= extract_nearby_stat_value(lines, /\b(?:str|strength)\b/i)
          data['DEX'] ||= extract_nearby_stat_value(lines, /\bdex\b/i)
          data['INT'] ||= extract_nearby_stat_value(lines, /\bint\b/i)
          data['LUK'] ||= extract_nearby_stat_value(lines, /\bluk\b/i)
          
          # More specific stats
          extract_patterns(normalized_text, data, {
            'DAMAGE RANGE' => Regexp.new("damage\\s*range[^\\n]*#{nl}#{millions}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'DAMAGE' => Regexp.new("damage#{nl}#{percent}(?!\\s*range)", Regexp::IGNORECASE | Regexp::MULTILINE),
            'FINAL DAMAGE' => Regexp.new("final\\s*damage#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'BOSS DAMAGE' => Regexp.new("boss\\s*damage#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'NORMAL ENEMY DAMAGE' => Regexp.new("normal\\s*enemy\\s*damage#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'IGNORE DEFENSE' => Regexp.new("ignore\\s*defense#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'ATTACK POWER' => Regexp.new("attack\\s*power#{nl}#{thousands}(?!\\s*[a-z])", Regexp::IGNORECASE | Regexp::MULTILINE),
            'CRITICAL RATE' => Regexp.new("critical\\s*rate[<>/b\\s]*#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'MAGIC ATT' => Regexp.new("magic\\s*att#{nl}#{thousands}(?!\\s*[a-z])", Regexp::IGNORECASE | Regexp::MULTILINE),
            'CRITICAL DAMAGE' => Regexp.new("critical\\s*damage[<>/b\\s]*#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'COOLDOWN REDUCTION' => Regexp.new("cooldown\\s*reduction#{nl}(\\d+)\\s*sec/\\s*(\\d+)%", Regexp::IGNORECASE | Regexp::MULTILINE),
            'BUFF DURATION' => Regexp.new("buff\\s*duration#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'COOLDOWN NOT APPLIED' => Regexp.new("cooldown\\s*not\\s*applied#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'IGNORE ELEMENTAL RESISTANCE' => Regexp.new("ignore\\s*elemental\\s*resistance#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'ADDITIONAL STATUS DAMAGE' => Regexp.new("additional\\s*status\\s*damage#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'SUMMONS DURATION INCREASE' => Regexp.new("summons\\s*duration\\s*increase#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'MESOS OBTAINED' => Regexp.new("mesos\\s*obtained#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'STAR FORCE' => Regexp.new("star\\s*force#{nl}#{thousands}(?!\\s*[a-z])", Regexp::IGNORECASE | Regexp::MULTILINE),
            'ITEM DROP RATE' => Regexp.new("item\\s*drop\\s*rate#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'ARCANE POWER' => Regexp.new("arcane\\s*power[<>/b\\s]*#{nl}#{thousands}(?!\\s*[a-z])", Regexp::IGNORECASE | Regexp::MULTILINE),
            'ADDITIONAL EXP OBTAINED' => Regexp.new("additional\\s*exp\\s*obtained#{nl}#{percent}", Regexp::IGNORECASE | Regexp::MULTILINE),
            'SACRED POWER' => Regexp.new("sacred\\s*power#{nl}#{thousands}(?!\\s*[a-z])", Regexp::IGNORECASE | Regexp::MULTILINE)
          }, match_index: 1, transform: ->(v) { 
            parsed = parse_numeric_value(v)
            parsed.nil? ? v : parsed
          })
          
          # Special handling for COOLDOWN REDUCTION (has two values: sec and %)
          if match = normalized_text.match(/cooldown\s*reduction#{nl}(\d+)\s*sec\/\s*(\d+)%/i)
            data['COOLDOWN REDUCTION'] = "#{match[1]} sec/#{match[2]}%"
          end
          
          # Map Combat Power to Gear Score
          data['Gear Score'] = data['Combat Power'] if data['Combat Power']
          
          data
        end

        private

        def extract_nearby_stat_value(lines, label_regex)
          label_index = lines.find_index { |line| line.match?(label_regex) }
          return nil unless label_index

          candidate_indexes = [label_index + 1, label_index + 2, label_index - 1]
          candidate_indexes.each do |candidate_index|
            next if candidate_index.negative? || candidate_index >= lines.length
            value = parse_ocr_number(lines[candidate_index])
            return value if value
          end

          nil
        end

        def parse_ocr_number(line)
          return nil unless line.is_a?(String)
          return nil if line.match?(/[A-Za-z]/)

          match = line.match(/([-\+−•·\d,.\s]+)/)
          return nil unless match

          parsed = parse_numeric_value(match[1])
          return nil unless parsed.is_a?(Numeric)

          parsed.to_i
        end

        def parse_numeric_value(value)
          return nil unless value.is_a?(String)

          normalized = value.dup
            .tr('−', '-')
            .gsub(/[•·]/, '')
            .gsub(/\s+/, '')
            .gsub('%', '')
            .sub(/\A[+-]/, '')

          # OCR sometimes uses "." as thousands separator (e.g., "2.694")
          normalized = normalized.gsub(/\.(\d{3})$/, ',\1').gsub(',', '')
          return nil unless normalized.match?(/\A\d+(?:\.\d+)?\z/)

          normalized.include?('.') ? normalized.to_f : normalized.to_i
        end
      end
    end
  end
end

