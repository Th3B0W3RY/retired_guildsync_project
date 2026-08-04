# frozen_string_literal: true

module StatScanner
  # Second line of defense when OCR returns plain text without layout (non-Azure or API fallback).
  # For Azure, lib/scripts/azure_ocr.js also trims by bounding boxes (left/right/bottom HUD) so stat
  # scans prefer character / detail panels across games, not chat regions.
  # Drops lines that commonly come from MMO chat / system feeds, not stat panels.
  class OcrTextPrefilter
    # [Channel] PlayerName: message (chat)
    CHAT_NAME_COLON = /\A\[[^\]]{1,50}\]\s+\S+:\s*\S+/u
    # Some clients emit nested tags before the speaker (common in MMO logs).
    CHAT_DOUBLE_BRACKET = /\A\[[^\]]{1,50}\]\s*\[[^\]]{1,50}\]\s*:\s*\S+/u

    class << self
      def filter_for_stat_scan(text)
        return text unless text.is_a?(String) && text.present?

        text.each_line.map(&:chomp).reject { |line| chat_like_line?(line.strip) }.join("\n")
      end

      def chat_like_line?(s)
        return false if s.blank?

        return true if s.match?(CHAT_NAME_COLON)
        return true if s.match?(CHAT_DOUBLE_BRACKET)

        false
      end
    end
  end
end
