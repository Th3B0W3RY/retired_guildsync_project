# frozen_string_literal: true

module Games
  module FinalFantasyXiv
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          normalized_text = raw_text.to_s
            .gsub(/\b5trength\b/i, "strength")
            .gsub(/\bstength\b/i, "strength")
            .gsub(/\bstrengh\b/i, "strength")
            .gsub(/\bstrenqth\b/i, "strength")
          
          # Final Fantasy XIV - values appear on next line after label (no colon)
          # Pattern: "Strength\n120" where value is on next line
          # Note: Some attributes may have text on the same line (e.g., "Accuracy\n354 Defense\n375")
          nl = BaseOcrHandler::NEWLINE
          integer = '(\d+)'
          
          # Level (may appear as "EVEL 60" due to OCR error)
          if level_match = normalized_text.match(/(?:level|evel)\s+(\d+)/i)
            data['Level'] = level_match[1].to_i
          end
          
          # Average Item Level - pattern: "Average Item Level\n151"
          if item_level_match = normalized_text.match(/average\s*item\s*level\s*\n\s*(\d+)/i)
            data['Average Item Level'] = item_level_match[1].to_i
          end
          
          # HP/MP/TP (current/total format, extract total)
          # Pattern: "6686\n13104\n1000" or "<u> 6686</u>\n<u>м⊳13104</u>\nTP\n1000"
          # Look for three consecutive numbers or HP/MP/TP labels
          if hp_match = normalized_text.match(/(\d{3,})\s*\n\s*(\d{3,})\s*\n\s*(\d{3,})/)
            values = [hp_match[1], hp_match[2], hp_match[3]].map(&:to_i).sort.reverse
            data['HP'] = values[0] if values[0] > 1000
            data['MP'] = values[1] if values[1] > 1000
            data['TP'] = values[2] if values[2] > 100
          elsif tp_match = normalized_text.match(/tp#{nl}#{integer}/i)
            data['TP'] = tp_match[1].to_i
          end
          
          # Attributes (all int)
          # Pattern: "Strength\n120" - value on next line
          ['Bonus', 'Strength', 'Dexterity', 'Vitality', 'Mind', 'Piety'].each do |attr|
            if match = normalized_text.match(/#{attr.downcase}\s*(?:\n|\s+)\s*(?:[^\n\d][^\n]*\n\s*)?(\d+)/i)
              data[attr] = match[1].to_i
            end
          end
          
          # Intelligence (may be misspelled as "intellabence")
          if int_match = normalized_text.match(/(?:intelligence|intellabence)\s*(?:\n|\s+)\s*(?:[^\n\d][^\n]*\n\s*)?(\d+)/i)
            data['Intelligence'] = int_match[1].to_i
          end
          
          # Elemental Resistances (all int) - pattern: "Fire\n282"
          ['Fire', 'Ice', 'Wind', 'Earth', 'Lightning'].each do |elem|
            if match = normalized_text.match(/#{elem.downcase}\s*(?:\n|\s+)\s*(\d+)/i)
              data["#{elem} Resistance"] = match[1].to_i
            end
          end
          
          # Water (may be misspelled as "₩ater")
          if water_match = normalized_text.match(/(?:water|₩ater)\s*(?:\n|\s+)\s*(\d+)/i)
            data['Water Resistance'] = water_match[1].to_i
          end
          
          # Offensive Properties (all int)
          # Note: "Accuracy\n354 Defense\n375" - both on same line, extract Accuracy first
          if accuracy_match = normalized_text.match(/accuracy\s*(?:\n|\s+)\s*(\d+)/i)
            data['Accuracy'] = accuracy_match[1].to_i
          end
          
          if crit_match = normalized_text.match(/critical\s*hit\s*rate\s*(?:\n|\s+)\s*(\d+)/i)
            data['Critical Hit Rate'] = crit_match[1].to_i
          end
          
          if det_match = normalized_text.match(/determination\s*(?:\n|\s+)\s*(\d+)/i)
            data['Determination'] = det_match[1].to_i
          end
          
          # Defensive Properties (all int)
          # Note: "Accuracy\n354 Defense\n375" - Defense is on same line as Accuracy value
          if defense_match = normalized_text.match(/defense\s*(?:\n|\s+)\s*(\d+)/i)
            data['Defense'] = defense_match[1].to_i
          end
          
          if parry_match = normalized_text.match(/parry\s*(?:\n|\s+)\s*(\d+)/i)
            data['Parry'] = parry_match[1].to_i
          end
          
          if magic_def_match = normalized_text.match(/magic\s*defense\s*(?:\n|\s+)\s*(\d+)/i)
            data['Magic Defense'] = magic_def_match[1].to_i
          end
          
          # Physical Properties (all int)
          # Note: "Attack Power\n120 Attack Magic Potency\n226" - both on same line
          if attack_power_match = normalized_text.match(/attack\s*power\s*(?:\n|\s+)\s*(\d+)/i)
            data['Attack Power'] = attack_power_match[1].to_i
          end
          
          if attack_magic_match = normalized_text.match(/attack\s*magic\s*potency\s*(?:\n|\s+)\s*(\d+)/i)
            data['Attack Magic Potency'] = attack_magic_match[1].to_i
          end
          
          if skill_speed_match = normalized_text.match(/skill\s*speed\s*(?:\n|\s+)\s*(\d+)/i)
            data['Skill Speed'] = skill_speed_match[1].to_i
          end
          
          # Mental Properties (all int)
          # Note: "Healing Magic Potency 720" - value on same line (no newline)
          if healing_match = normalized_text.match(/healing\s*magic\s*potency\s+(\d+)/i)
            data['Healing Magic Potency'] = healing_match[1].to_i
          end
          
          if spell_speed_match = normalized_text.match(/spell\s*speed\s*(?:\n|\s+)\s*(\d+)/i)
            data['Spell Speed'] = spell_speed_match[1].to_i
          end
          
          # Map item level to gear score if present
          data['Gear Score'] = data['Average Item Level'] if data['Average Item Level']
          
          data
        end
      end
    end
  end
end

