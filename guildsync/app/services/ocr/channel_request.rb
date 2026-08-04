# frozen_string_literal: true

module Ocr
  # Duck-typed stand-in for a Rack request when OCR runs outside HTTP (e.g. Discord).
  # Ocr::UsageTracker and OcrRequest only need +remote_ip+ and +user_agent+.
  class ChannelRequest
    attr_reader :remote_ip, :user_agent

    # @param user_agent [String] stored on OcrRequest (truncated)
    # @param remote_ip [String, nil] omit for non-HTTP channels (per-IP quota is skipped when blank)
    def initialize(user_agent:, remote_ip: nil)
      @remote_ip = remote_ip.presence
      @user_agent = user_agent.to_s.truncate(500)
    end

    def self.for_discord_gear_upload
      new(user_agent: "Discord/gear-upload")
    end
  end
end
