module Games
  module NewWorld
    class OcrHandler < BaseOcrHandler
      class << self
        def parse_gear_data(raw_text, base_data, config)
          # Supplement base parsing with game-specific logic
          data = base_data.dup
          
          # New World specific parsing
          # Example: Extract gear score from specific format
          if match = raw_text.match(/Gear\s*Score[:\s]*(\d+)/i)
            data['Gear Score'] = match[1].to_i
          end
          
          # Example: Parse weapon slots (New World has multiple weapon slots)
          weapon_matches = raw_text.scan(/Weapon\s*(\d+)[:\s]+([^\n]+)/i)
          weapon_matches.each_with_index do |(num, name), index|
            data["Weapon #{num}"] = name.strip
          end
          
          # Example: Validate required fields
          required_fields = ['Gear Score', 'Weapon 1']
          missing_fields = required_fields - data.keys
          if missing_fields.any?
            Rails.logger.warn "Missing required fields for New World: #{missing_fields.join(', ')}"
          end
          
          # Example: Transform data structure
          data['gear_tier'] = calculate_gear_tier(data['Gear Score']) if data['Gear Score']
          
          data
        end
        
        private
        
        def calculate_gear_tier(gear_score)
          case gear_score
          when 0..500 then 'Tier 1'
          when 501..600 then 'Tier 2'
          when 601..625 then 'Tier 3'
          else 'Tier 4'
          end
        end
      end
    end
  end
end

