require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Secret key base is required for production
  # Must be set via SECRET_KEY_BASE environment variable
  # Generate with: rails secret
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") do
    raise ArgumentError, "SECRET_KEY_BASE environment variable is required for production. Set it with: export SECRET_KEY_BASE=$(rails secret)"
  end

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory usage.
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Enable static file serving from the `/public` folder (turn off if using NGINX/Apache for it).
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present? || ENV["RENDER"].present?

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fall back to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Active Storage service selection:
  # - ACTIVE_STORAGE_SERVICE can force a service (e.g. amazon/local)
  # - otherwise use S3 when required vars are present and aws-sdk-s3 is available
  forced_service = ENV["ACTIVE_STORAGE_SERVICE"].presence
  if forced_service.present?
    config.active_storage.service = forced_service.to_sym
  else
    s3_bucket = ENV["S3_BUCKET"].presence || ENV["AWS_S3_BUCKET_NAME"].presence || ENV["AWS_BUCKET"]
    s3_key = ENV["S3_ACCESS_KEY_ID"].presence || ENV["AWS_ACCESS_KEY_ID"]
    s3_secret = ENV["S3_SECRET_ACCESS_KEY"].presence || ENV["AWS_SECRET_ACCESS_KEY"]
    s3_gem_ok = begin
      require "aws-sdk-s3"
      true
    rescue Gem::LoadError, LoadError
      false
    end

    s3_configured = s3_bucket.present? && s3_key.present? && s3_secret.present? && s3_gem_ok
    config.active_storage.service = s3_configured ? :amazon : :local

    if !s3_configured
      missing = []
      missing << "S3_BUCKET" if s3_bucket.blank?
      missing << "S3_ACCESS_KEY_ID" if s3_key.blank?
      missing << "S3_SECRET_ACCESS_KEY" if s3_secret.blank?
      missing << "aws-sdk-s3 gem availability" unless s3_gem_ok
      puts "Active Storage fallback to :local in production (missing: #{missing.join(', ')})"
    end
  end

  # Action Cable: adapter and URL come from config/cable.yml in Rails 8
  config.action_cable.mount_path = "/cable"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Explicit HSTS policy: 1-year max-age, include subdomains, eligible for browser preload lists.
  # Rails default only sets max-age=31536000 without subdomains/preload.
  config.ssl_options = {
    hsts: {
      expires: 1.year.to_i,
      subdomains: true,
      preload: true
    }
  }

  # Trust proxies (for reverse proxy/load balancer setups)
  config.action_dispatch.trusted_proxies = [
    IPAddr.new("127.0.0.1"),
    IPAddr.new("::1")
  ]

  # Logging: Rails.logger and all system logs are configured in config/initializers/logging.rb
  # and use GUILDSYNC_LOG_DIR from .env when set. Do not override config.logger here.

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set this to "debug".
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use a different cache store in production.
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" },
    namespace: "guildsync:cache",
    expires_in: 90.minutes,
    reconnect_attempts: 3
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Use Sidekiq for background jobs
  config.active_job.queue_adapter = :sidekiq

  # Action Mailer and URL generation (redirect_uri for Discord OAuth must match exactly)
  config.action_mailer.perform_caching = false
  mailer_protocol = ENV.fetch("MAILER_URL_PROTOCOL", "https")
  mailer_host = ENV.fetch("HOST", "guild-sync.net")
  config.action_mailer.default_url_options = { host: mailer_host, protocol: mailer_protocol }
  config.action_controller.default_url_options = { host: mailer_host, protocol: mailer_protocol }

  # Transactional email: Resend SMTP (credentials from ENV only — see guildsync/.env.example).
  # Variable names are generic SMTP; Resend values: https://resend.com/docs/send-with-smtp
  # smtp_settings are applied in config/initializers/production_action_mailer_smtp.rb via
  # GuildSync::ProductionActionMailerSmtp (after_initialize) so db:migrate and boot can load
  # before app/services constants resolve. Misconfiguration (e.g. implicit localhost:25) fails fast there.
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.raise_delivery_errors = ENV.fetch("SMTP_RAISE_DELIVERY_ERRORS", "true") == "true"

  # Asset pipeline configuration
  config.assets.enabled = true
  config.assets.digest = true
  config.assets.version = "1.0"

  # Public file server headers
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=31536000, immutable"
  }
end
