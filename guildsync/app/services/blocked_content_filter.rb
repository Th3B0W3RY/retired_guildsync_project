# frozen_string_literal: true

# Checks text against a blocklist (profanity, slurs, abuse) using word boundaries.
# Uses BlockedWord table when present, else config/blocked_content.yml.
# Caches terms for 6 hours; ProfanityListUpdateJob invalidates cache on update.
class BlockedContentFilter
  CACHE_KEY = "blocked_words_list"
  CACHE_TTL = 6.hours

  class << self
    def blocked?(text)
      return false if text.blank?
      scan(text).any?
    end

    def scan(text)
      return [] if text.blank?
      triggered = []
      terms.each do |term|
        pattern = /\b#{Regexp.escape(term)}\b/i
        triggered << term if text.match?(pattern)
      end
      triggered.uniq
    end

    def terms
      @terms ||= fetch_terms
    end

    def reset!
      @terms = nil
      Rails.cache.delete(CACHE_KEY) if defined?(Rails.cache)
    end

    private

    def fetch_terms
      return load_terms unless defined?(Rails.cache)
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { load_terms }
    end

    def load_terms
      if defined?(BlockedWord) && BlockedWord.table_exists?
        db_terms = BlockedWord.terms_for_filter
        return db_terms if db_terms.any?
      end
      path = Rails.root.join("config", "blocked_content.yml")
      return [] unless File.exist?(path)
      list = YAML.load_file(path)
      list.is_a?(Array) ? list.map(&:to_s).map(&:strip).reject(&:blank?) : []
    end
  end
end
