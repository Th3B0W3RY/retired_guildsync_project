# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Server-side verification for Cloudflare Turnstile (signup bot protection).
# Set TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY in the environment.
# When either is blank, verification is skipped (local dev without keys).
class TurnstileVerificationService
  SITEVERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  class << self
    def enforced?
      ENV["TURNSTILE_SITE_KEY"].present? && ENV["TURNSTILE_SECRET_KEY"].present?
    end

    # @return [:ok, :missing_token, :invalid, :error]
    def verify(response_token:, remote_ip: nil)
      return :ok unless enforced?

      # Playwright / long-running `rails server -e test` often loads .env with real Turnstile keys.
      # Without this, API sign_up returns 422 for a missing token even though RSpec uses the same
      # keys only when opting into strict checks via TURNSTILE_STRICT_IN_TEST=1 (signup_turnstile_spec).
      if Rails.env.test? && ENV["TURNSTILE_STRICT_IN_TEST"] != "1" && response_token.blank?
        return :ok
      end

      if response_token.blank?
        return :missing_token
      end

      uri = URI(SITEVERIFY_URL)
      body = {
        "secret" => ENV["TURNSTILE_SECRET_KEY"].to_s,
        "response" => response_token.to_s
      }
      body["remoteip"] = remote_ip.to_s if remote_ip.present?

      res = Net::HTTP.post_form(uri, body)
      json = JSON.parse(res.body)
      if json["success"] == true
        :ok
      else
        Rails.logger.warn("Turnstile verification failed: #{json.inspect}")
        :invalid
      end
    rescue JSON::ParserError => e
      Rails.logger.error("Turnstile verify error: #{e.class}: #{e.message}")
      :error
    rescue StandardError => e
      Rails.logger.error("Turnstile verify error: #{e.class}: #{e.message}")
      :error
    end
  end
end
