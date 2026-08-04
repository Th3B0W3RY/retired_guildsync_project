# frozen_string_literal: true

# Redis Configuration
# This initializer sets up Redis connection for caching and Sidekiq
#
# Environment Variables:
# - REDIS_URL: Full Redis connection URL (e.g., redis://localhost:6379/0)
#              Use rediss:// scheme to enable TLS (required for hosted Redis in production)
# - REDIS_HOST: Redis host (default: localhost)
# - REDIS_PORT: Redis port (default: 6379)
# - REDIS_CACHE_DB: Redis database number for cache (default: 0)
# - REDIS_SIDEKIQ_DB: Redis database number for Sidekiq (default: 1)
# - REDIS_PASSWORD: Redis password (if required)
# - REDIS_SSL_VERIFY_NONE: Set to "1" to skip TLS certificate verification (e.g. self-signed certs)

module RedisConfig
  # Build Redis URL from environment variables or use default
  def self.url(db: 0)
    if ENV["REDIS_URL"].present?
      # If full URL provided, optionally change database number
      base_url = ENV["REDIS_URL"]
      if db != 0 && base_url.match?(%r{/\d+$})
        base_url.gsub(%r{/\d+$}, "/#{db}")
      else
        base_url
      end
    else
      # Build URL from components
      host = ENV.fetch("REDIS_HOST", "localhost")
      port = ENV.fetch("REDIS_PORT", "6379")
      password = ENV["REDIS_PASSWORD"]

      url = "redis://"
      url += ":#{password}@" if password.present?
      url += "#{host}:#{port}/#{db}"
      url
    end
  end

  # Returns SSL options when the resolved URL uses the rediss:// scheme.
  # REDIS_SSL_VERIFY_NONE=1 disables peer verification for self-signed certificates.
  def self.ssl_options(redis_url)
    return {} unless redis_url.to_s.start_with?("rediss://")

    verify_mode = ENV["REDIS_SSL_VERIFY_NONE"].to_s == "1" ?
      OpenSSL::SSL::VERIFY_NONE :
      OpenSSL::SSL::VERIFY_PEER

    { ssl: true, ssl_params: { verify_mode: verify_mode } }
  end

  # Redis connection options
  def self.connection_options
    resolved_url = url
    {
      url: resolved_url,
      reconnect_attempts: 3,
      reconnect_delay: 0.5,
      reconnect_delay_max: 2.0,
      timeout: 5
    }.merge(ssl_options(resolved_url))
  end

  # Cache-specific Redis URL (database 0)
  def self.cache_url
    url(db: ENV.fetch("REDIS_CACHE_DB", "0").to_i)
  end

  # Sidekiq-specific Redis URL (database 1)
  def self.sidekiq_url
    url(db: ENV.fetch("REDIS_SIDEKIQ_DB", "1").to_i)
  end

  # SSL options for a specific URL (used by Sidekiq and Action Cable configs)
  def self.ssl_options_for(redis_url)
    ssl_options(redis_url)
  end
end
