# frozen_string_literal: true

module ContentModeration
  # Runs content against the blocked-words filter. Returns :approved or :pending with triggered words.
  # Does not save anything; callers set moderation_status and save the record.
  class FilterService
    PENDING_MESSAGE = "Your submission contains inappropriate language and has been sent for review."

    def initialize(content_text, content_type:, user: nil)
      @content_text = content_text.to_s
      @content_type = content_type
      @user = user
    end

    def process
      return { status: :approved, bypass: true } if trusted_user?
      triggered = scan_for_blocked_words(@content_text)
      if triggered.any?
        increment_triggered_counts(triggered)
        return {
          status: :pending,
          message: PENDING_MESSAGE,
          triggered_words: triggered
        }
      end
      { status: :approved }
    end

    # Public for health-check job: scan text and return list of triggered words.
    def scan_for_blocked_words(text)
      BlockedContentFilter.scan(text.to_s)
    end

    private

    def trusted_user?
      return false unless @user
      return true if @user.respond_to?(:trusted?) && @user.trusted?
      false
    end

    def increment_triggered_counts(words)
      return unless defined?(BlockedWord) && BlockedWord.table_exists?
      BlockedWord.active.where(word: words).update_all("times_triggered = times_triggered + 1")
    rescue => e
      Rails.logger.warn "ContentModeration::FilterService increment_triggered_counts: #{e.message}"
    end
  end
end
