module Games
  class BaseOcrHandler
    # Base class for game-specific OCR data parsing
    # Subclasses can override parse_gear_data to customize parsing logic
    
    # Common regex pattern constants for reuse across handlers
    NEWLINE = '\s*\n\s*'  # Matches optional whitespace, newline, optional whitespace
    THOUSANDS_NUMBER = '([\d,]+)'  # Matches numbers with potential thousands separators (e.g., "1,495")
    DECIMAL_NUMBER = '([\d.]+)'  # Matches decimal numbers (e.g., "351.2")
    PERCENTAGE = '([\d.]+(?:%)?)'  # Matches numbers with optional percentage sign (e.g., "56.8%")
    
    class << self
      # Override this method in subclasses to customize parsing
      # @param raw_text [String] The full OCR text output
      # @param base_data [Hash] The data parsed from base patterns (can be modified)
      # @param config [Hash] The game's OCR config
      # @return [Hash] The parsed gear data
      def parse_gear_data(raw_text, base_data, config)
        # Default implementation: return base_data (patterns already applied)
        # Subclasses can:
        # 1. Modify base_data
        # 2. Add additional parsing logic
        # 3. Validate/clean data
        # 4. Transform data structure
        base_data
      end
      
      # Centralized pattern matching helper
      # Extracts values from raw_text using regex patterns and stores them in data hash
      # @param raw_text [String] The full OCR text output
      # @param data [Hash] The data hash to populate
      # @param patterns [Hash] Hash of key => regex pattern pairs
      #   Example: { 'Gear Score' => /gear\s*score[:\s]*(\d+)/i, 'Level' => /level[:\s]*(\d+)/i }
      # @param options [Hash] Options for extraction
      #   - :match_index [Integer] Which capture group to use (default: 1)
      #   - :transform [Proc] Optional proc to transform the matched value
      #   - :required [Boolean] Whether to log warning if not found (default: false)
      def extract_patterns(raw_text, data, patterns, options = {})
        match_index = options[:match_index] || 1
        transform = options[:transform]
        required = options[:required] || false
        multiline = options[:multiline] != false  # Default to true for multiline matching
        
        patterns.each do |key, pattern|
          if pattern.is_a?(Regexp)
            # If it's already a Regexp, check if it has multiline flag
            # If not, we need to create a new one with multiline flag
            flags = pattern.options
            unless flags & Regexp::MULTILINE == Regexp::MULTILINE
              # Recreate regex with multiline flag if needed
              regex = Regexp.new(pattern.source, flags | Regexp::MULTILINE)
            else
              regex = pattern
            end
          else
            # Convert string to Regexp with appropriate flags
            flags = Regexp::IGNORECASE
            flags |= Regexp::MULTILINE if multiline
            regex = Regexp.new(pattern.to_s, flags)
          end
          
          if match = raw_text.match(regex)
            value = match[match_index]
            value = transform.call(value) if transform
            data[key] = value
          elsif required
            Rails.logger.warn "Required pattern not found for key: #{key}"
          end
        end
        
        data
      end
      
      # Extract multiple occurrences of a pattern (e.g., multiple weapon slots)
      # @param raw_text [String] The full OCR text output
      # @param data [Hash] The data hash to populate
      # @param pattern [Regexp] Pattern to match
      # @param key_prefix [String] Prefix for keys (e.g., "Weapon" becomes "Weapon 1", "Weapon 2", etc.)
      # @param options [Hash] Options for extraction
      def extract_multiple(raw_text, data, pattern, key_prefix, options = {})
        match_index = options[:match_index] || 1
        transform = options[:transform]
        
        matches = raw_text.scan(pattern)
        matches.each_with_index do |match, index|
          value = match.is_a?(Array) ? match[match_index - 1] : match
          value = transform.call(value) if transform
          key = matches.length > 1 ? "#{key_prefix} #{index + 1}" : key_prefix
          data[key] = value
        end
        
        data
      end
      
      # Optional: Override to customize image preprocessing
      # @param image_path [String] Path to image file
      # @return [String] Path to preprocessed image (or original if no preprocessing)
      def preprocess_image(image_path)
        image_path
      end
    end
  end
end

