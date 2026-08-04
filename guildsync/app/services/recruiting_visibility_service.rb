# frozen_string_literal: true

# Hides guild from public recruiting when the name contains severe blocked terms (configurable list).
class RecruitingVisibilityService
  BLOCKLIST = %w[
    nazi hitler kkk slur
  ].freeze

  class << self
    def publicly_recruitable?(guild_or_name)
      name = guild_or_name.is_a?(String) ? guild_or_name : guild_or_name&.name
      return true if name.blank?
      normalized = name.downcase
      BLOCKLIST.none? { |w| normalized.include?(w) }
    end

    # Substrings from BLOCKLIST present in any of the given strings (downcased). Used by roadmap moderation so the
    # same severe terms as public recruiting stay out of public feature text even when not in the profanity word list.
    def matching_severe_terms(*strings)
      texts = strings.flatten.compact.map { |s| s.to_s.downcase }
      return [] if texts.all?(&:blank?)

      BLOCKLIST.select { |word| texts.any? { |t| t.include?(word) } }
    end
  end
end
