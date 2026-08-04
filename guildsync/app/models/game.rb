class Game < ApplicationRecord

  has_many :guild_games, dependent: :destroy
  has_many :guilds, through: :guild_games
  has_many :gear_snapshots, dependent: :destroy
  belongs_to :deactivated_by, class_name: "User", optional: true, foreign_key: "deactivated_by_id"

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

  scope :active, -> { where(active: true) }
  scope :pending, -> { where(active: false, deactivated_at: nil) } # Never activated
  scope :deactivated, -> { where(active: false).where.not(deactivated_at: nil) } # Was active but deactivated

  # Conditional scopes - only work if columns exist (added in AddIgdbFieldsToGames migration)
  scope :guild_oriented, -> {
    if column_names.include?("guild_oriented")
      where(guild_oriented: true)
    else
      all # Return all if column doesn't exist yet
    end
  }

  scope :verified_by_igdb, -> {
    if column_names.include?("verified_by_igdb")
      where(verified_by_igdb: true)
    else
      all # Return all if column doesn't exist yet
    end
  }

  scope :needs_igdb_sync, -> {
    if column_names.include?("igdb_synced_at")
      where("igdb_synced_at IS NULL OR igdb_synced_at < ?", 24.hours.ago)
    else
      none # Return none if column doesn't exist yet (no games need syncing)
    end
  }
  scope :fuzzy_search, ->(query) {
    return none if query.blank?
    sanitized = ActiveRecord::Base.sanitize_sql_like(query)
    where("name ILIKE ?", "%#{sanitized}%")
  }

  # Calculate similarity score for fuzzy matching (0.0 to 1.0)
  # Uses Levenshtein-like approach with case-insensitive comparison
  def similarity_score(other_name)
    return 1.0 if name.downcase == other_name.downcase
    return 0.0 if other_name.blank?

    # Simple similarity: check if one contains the other
    if name.downcase.include?(other_name.downcase) || other_name.downcase.include?(name.downcase)
      shorter = [ name.length, other_name.length ].min
      longer = [ name.length, other_name.length ].max
      return (shorter.to_f / longer) * 0.8 # Partial match gets 0.8 max
    end

    # Calculate character overlap
    name_chars = name.downcase.chars.uniq
    other_chars = other_name.downcase.chars.uniq
    common_chars = name_chars & other_chars
    total_chars = (name_chars | other_chars).size

    return 0.0 if total_chars.zero?
    (common_chars.size.to_f / total_chars) * 0.6 # Character overlap gets 0.6 max
  end

  # Find similar games with similarity scores
  def self.find_similar(query, limit: 5, min_similarity: 0.3)
    return [] if query.blank?

    query_normalized = query.strip.downcase

    # First, try exact and partial matches
    exact_matches = where("LOWER(name) = ?", query_normalized)
    partial_matches = fuzzy_search(query).where.not(id: exact_matches.select(:id))

    # Calculate similarity for all candidates
    all_candidates = (exact_matches + partial_matches).uniq

    scored = all_candidates.map do |game|
      score = game.similarity_score(query)
      { game: game, score: score }
    end

    # Filter by minimum similarity and sort by score
    scored.select { |item| item[:score] >= min_similarity }
          .sort_by { |item| -item[:score] }
          .first(limit)
          .map { |item| item[:game] }
  end

  # OCR config structure:
  # {
  #   "patterns": [
  #     {"type": "label_value", "regex": "([A-Za-z\\s]+):\\s*([^\\n]+)"},
  #     {"type": "gear_score", "regex": "(?:Gear\\s+Score|GS)[:\\s]+(\\d+)"},
  #     {"type": "weapon", "regex": "(?:Weapon\\s*1?)[:\\s]+([^\\n]+)"}
  #   ],
  #   "common_fields": ["Gear Score", "Weapon 1", "Helmet", "Armor"],
  #   "handler_class": "Games::NewWorld::OcrHandler" (optional)
  # }

  def parse_gear_data(raw_text)
    Rails.logger.debug "Game#parse_gear_data: Starting parsing for game: #{name}"
    config = ocr_config || {}
    handler_class_name = config["handler_class"]
    Rails.logger.debug "Game#parse_gear_data: Handler class: #{handler_class_name || 'none'}, Patterns: #{config['patterns'] ? 'configured' : 'none'}"

    # If handler is present, it is the PRIMARY source - skip base patterns
    # Handlers should do all parsing themselves
    if handler_class_name.present?
      begin
        handler_class = handler_class_name.constantize
        if handler_class < Games::BaseOcrHandler
          # Handler is primary - start with empty base_data
          # Handler can use base_data as a starting point if needed, but typically will do all parsing itself
          base_data = {}
          result = handler_class.parse_gear_data(raw_text, base_data, config)
          Rails.logger.debug "Game#parse_gear_data: Handler returned #{result.keys.size} fields: #{result.keys.inspect}"
          return result
        else
          Rails.logger.warn "Handler class #{handler_class_name} does not inherit from Games::BaseOcrHandler"
        end
      rescue NameError => e
        Rails.logger.error "Handler class #{handler_class_name} not found: #{e.message}"
      rescue => e
        Rails.logger.error "Error using handler class #{handler_class_name}: #{e.message}"
      end
    end

    # Step 2: Apply base pattern-based parsing (only if no handler or handler failed)
    # This is a fallback for games without handlers
    patterns = config["patterns"] || {}
    base_data = {}

    # Support both hash format: { 'gear_score' => /regex/ } and array format: [{ 'type' => 'gear_score', 'regex' => '...' }]
    if patterns.is_a?(Hash)
      # Hash format: keys are pattern types, values are regex patterns
      patterns.each do |pattern_type, regex_pattern|
        # Convert string regex to Regexp if needed
        regex = regex_pattern.is_a?(Regexp) ? regex_pattern : Regexp.new(regex_pattern.to_s, Regexp::IGNORECASE)

        case pattern_type.to_s
        when "gear_score"
          if match = raw_text.match(regex)
            base_data["Gear Score"] = match[1].to_i
          end
        when "item_level"
          if match = raw_text.match(regex)
            base_data["Item Level"] = match[1].to_i
          end
        when "weapon"
          if match = raw_text.match(regex)
            base_data["Weapon 1"] = match[1].strip
          end
        when "armor"
          if match = raw_text.match(regex)
            base_data["Armor"] = match[1].strip
          end
        when "accessories", "accessory"
          if match = raw_text.match(regex)
            base_data["Accessories"] = match[1].strip
          end
        when "label_value"
          # Generic label:value pattern
          raw_text.scan(regex) do |label, value|
            clean_label = label.strip
            clean_value = value.strip
            base_data[clean_label] = clean_value unless clean_label.empty?
          end
        else
          # Generic pattern - try to extract first capture group
          if match = raw_text.match(regex)
            # Use pattern type as key, or first capture group as value
            key = pattern_type.to_s.split("_").map(&:capitalize).join(" ")
            base_data[key] = match[1] ? match[1].strip : match[0].strip
          end
        end
      end
    elsif patterns.is_a?(Array)
      # Array format: [{ 'type' => 'gear_score', 'regex' => '...' }]
      patterns.each do |pattern|
        pattern_type = pattern["type"] || pattern[:type]
        regex_str = pattern["regex"] || pattern[:regex]
        next unless pattern_type && regex_str

        regex = Regexp.new(regex_str, Regexp::IGNORECASE)

        case pattern_type.to_s
        when "label_value"
          raw_text.scan(regex) do |label, value|
            clean_label = label.strip
            clean_value = value.strip
            base_data[clean_label] = clean_value unless clean_label.empty?
          end
        when "gear_score"
          if match = raw_text.match(regex)
            base_data["Gear Score"] = match[1].to_i
          end
        when "weapon"
          if match = raw_text.match(regex)
            base_data["Weapon 1"] = match[1].strip
          end
          # Add more pattern types as needed
        end
      end
    end

    # Fallback to generic pattern matching if no patterns configured or nothing was extracted
    if base_data.empty?
      Rails.logger.debug "Game#parse_gear_data: No patterns matched, trying fallback parsing"
      # Try label:value pattern first (with colon)
      raw_text.scan(/([A-Za-z\s]+):\s*([^\n]+)/) do |label, value|
        clean_label = label.strip
        clean_value = value.strip
        base_data[clean_label] = clean_value unless clean_label.empty?
      end
      Rails.logger.debug "Game#parse_gear_data: After colon pattern: #{base_data.keys.size} fields"

      # If still empty, try label on one line, value on next line (common in game UIs)
      if base_data.empty?
        lines = raw_text.split("\n").map(&:strip).reject(&:empty?)
        Rails.logger.debug "Game#parse_gear_data: Trying line-by-line parsing with #{lines.size} lines"
        lines.each_with_index do |line, index|
          next if index == lines.length - 1 # Skip last line (no next line)

          # Check if current line looks like a label (letters/spaces, no numbers)
          # and next line looks like a value (numbers, possibly with commas/decimals/percentages)
          if line.match?(/^[A-Za-z\s]+$/) && !line.match?(/\d/)
            next_line = lines[index + 1]
            # Next line should contain numbers
            if next_line.match?(/[\d,.\-%]+/)
              clean_label = line.strip
              clean_value = next_line.strip
              # Skip if we already have this label (avoid duplicates)
              base_data[clean_label] = clean_value unless base_data.key?(clean_label)
            end
          end
        end
        Rails.logger.debug "Game#parse_gear_data: After line-by-line pattern: #{base_data.keys.size} fields"
      end
    end

    Rails.logger.debug "Game#parse_gear_data: Final result: #{base_data.keys.size} fields extracted: #{base_data.keys.inspect}"
    # Return base data (fallback when no handler)
    base_data
  end

  # Status helpers
  def pending?
    !active? && deactivated_at.nil?
  end

  def deactivated?
    !active? && deactivated_at.present?
  end

  def was_ever_active?
    deactivated_at.present? || active?
  end
end
