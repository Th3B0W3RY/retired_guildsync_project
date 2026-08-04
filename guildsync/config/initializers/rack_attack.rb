# frozen_string_literal: true

# Mirrors ::AccountDeletion::RateLimits (avoid autoloading app code before Rails finishes boot).
ACCOUNT_DELETION_RACK_SEND_LIMIT = Integer(ENV.fetch("ACCOUNT_DELETION_SEND_LIMIT_PER_HOUR", "5"))
ACCOUNT_DELETION_RACK_CONFIRM_LIMIT = Integer(ENV.fetch("ACCOUNT_DELETION_CONFIRM_LIMIT_PER_HOUR", "20"))
PROFILE_EMAIL_VERIFICATION_RACK_LIMIT = Integer(ENV.fetch("PROFILE_EMAIL_VERIFICATION_SEND_LIMIT_PER_HOUR", "10"))

class Rack::Attack
  def self.rate_limit_headers_from_match_data(match_data)
    return {} unless match_data.is_a?(Hash)

    limit = match_data[:limit].to_i
    count = match_data[:count].to_i
    period = match_data[:period].to_i
    epoch_time = match_data[:epoch_time].to_i

    return {} if limit <= 0

    remaining = [ limit - count, 0 ].max
    reset_at = if epoch_time > 0 && period > 0
      epoch_time + period
    else
      Time.now.to_i + [ period, 1 ].max
    end

    {
      "X-RateLimit-Limit" => limit.to_s,
      "X-RateLimit-Remaining" => remaining.to_s,
      "X-RateLimit-Reset" => reset_at.to_s
    }
  end

  # Configure cache store for Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Completely disable rate limiting in test environment
  if Rails.env.test?
    # No throttling in test - allow unlimited requests
    # This ensures tests can run without rate limit interference
  elsif Rails.env.development?
    # Very permissive limits for development
    throttle("req/ip", limit: 10000, period: 1.minute) do |req|
      req.ip
    end

    throttle("logins/ip", limit: 1000, period: 1.minute) do |req|
      if req.path == "/api/v1/auth/sign_in" && req.post?
        req.ip
      end
    end

    throttle("signups/ip", limit: 1000, period: 1.minute) do |req|
      if req.path == "/api/v1/auth/sign_up" && req.post?
        req.ip
      end
    end

    throttle("account_creation/ip", limit: 1000, period: 1.minute) do |req|
      if req.path.in?(%w[/create_account /create_account/resend]) && req.post?
        req.ip
      end
    end

    throttle("account_deletion/send_code/ip", limit: ACCOUNT_DELETION_RACK_SEND_LIMIT, period: 1.hour) do |req|
      req.ip if req.path == "/account/deletion/send_code" && req.post?
    end

    throttle("account_deletion/confirm/ip", limit: ACCOUNT_DELETION_RACK_CONFIRM_LIMIT, period: 1.hour) do |req|
      req.ip if req.path == "/account/deletion/confirm" && req.post?
    end

    throttle("profile_email_verification/ip", limit: 1000, period: 1.hour) do |req|
      req.ip if req.path == "/profile/settings/email_verification" && req.post?
    end
  else
    # Production rate limits
    # Throttle all requests by IP (60 requests per minute)
    throttle("req/ip", limit: 300, period: 5.minutes) do |req|
      req.ip
    end

    # Throttle login attempts by IP address
    throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
      if req.path == "/api/v1/auth/sign_in" && req.post?
        req.ip
      end
    end

    # Throttle sign up attempts by IP address
    throttle("signups/ip", limit: 3, period: 1.hour) do |req|
      if req.path == "/api/v1/auth/sign_up" && req.post?
        req.ip
      end
    end

    throttle("account_creation/ip", limit: 5, period: 1.hour) do |req|
      if req.path.in?(%w[/create_account /create_account/resend]) && req.post?
        req.ip
      end
    end

    throttle("account_creation/email", limit: 5, period: 1.day) do |req|
      if req.path.in?(%w[/create_account /create_account/resend]) && req.post?
        req.params["email"].to_s.downcase.strip.presence
      end
    end

    throttle("account_deletion/send_code/ip", limit: ACCOUNT_DELETION_RACK_SEND_LIMIT, period: 1.hour) do |req|
      req.ip if req.path == "/account/deletion/send_code" && req.post?
    end

    throttle("account_deletion/confirm/ip", limit: ACCOUNT_DELETION_RACK_CONFIRM_LIMIT, period: 1.hour) do |req|
      req.ip if req.path == "/account/deletion/confirm" && req.post?
    end

    throttle("profile_email_verification/ip", limit: PROFILE_EMAIL_VERIFICATION_RACK_LIMIT, period: 1.hour) do |req|
      req.ip if req.path == "/profile/settings/email_verification" && req.post?
    end
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"] || {}
    retry_after = match_data[:period] || 60
    rate_limit_headers = Rack::Attack.rate_limit_headers_from_match_data(match_data)

    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_s
      }.merge(rate_limit_headers),
      [ { error: "Rate limit exceeded. Please try again later." }.to_json ]
    ]
  end
end
