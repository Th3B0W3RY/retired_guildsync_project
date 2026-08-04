require "uri"

# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Active Storage service for test:
  # - default :test (disk-backed; avoids real S3 when .env sets ACTIVE_STORAGE_SERVICE=amazon for development)
  # - :amazon only when REAL_S3_UPLOADS_IN_SPECS=1 (must match spec/requests/active_storage_real_s3_uploads_spec.rb)
  forced_service = ENV["ACTIVE_STORAGE_SERVICE"].presence
  config.active_storage.service = if forced_service.to_s == "amazon"
    ENV["REAL_S3_UPLOADS_IN_SPECS"] == "1" ? :amazon : :test
  elsif forced_service.present?
    forced_service.to_sym
  else
    :test
  end

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates and URL helpers (e.g. Active Storage blob URLs).
  default_url_options = { host: "example.com" }
  if ENV["INTEGRATION_TESTS"] == "1" && ENV["APP_URL"].present?
    begin
      app_uri = URI.parse(ENV["APP_URL"])
      if app_uri.host.present?
        default_url_options = { host: app_uri.host, protocol: app_uri.scheme }
        default_url_options[:port] = app_uri.port if app_uri.port && ![80, 443].include?(app_uri.port)
      end
    rescue URI::InvalidURIError
      # Fall back to example.com so malformed local env does not prevent test boot.
    end
  end

  config.action_mailer.default_url_options = default_url_options
  config.action_controller.default_url_options = default_url_options
  config.after_initialize do
    Rails.application.routes.default_url_options = default_url_options
  end

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Enable logging in test environment conditionally
  # Set DEBUG=1 or LOG_LEVEL=debug to enable debug logging
  # Example: DEBUG=1 bundle exec rspec spec/requests/api/v1/guild_members_spec.rb
  if ENV["DEBUG"] == "1" || ENV["LOG_LEVEL"] == "debug"
    config.log_level = :debug
    # Optionally print logs to stdout during tests (can be verbose)
    # Uncomment the line below to also see logs in console
    # config.logger = ActiveSupport::Logger.new($stdout)
  else
    config.log_level = :warn
  end

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Use test adapter for background jobs in tests
  config.active_job.queue_adapter = :test
end
