require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test or :development.
ENV["DOTENV_NO_LOAD"] = "true" if ENV["RAILS_ENV"] == "test"
Bundler.require(*Rails.groups)

module GuildSync
  class Application < Rails::Application
    # Force development mode if RAILS_ENV is not set
    ENV["RAILS_ENV"] ||= "development"

    # Application version
    config.version = ENV.fetch("APP_VERSION", "1.0.0")

    # Load startup checkers
    config.after_initialize do
      # Skip startup checks for non-web rake tasks (matches SKIP_BOT_TASK_PREFIXES
      # in config/initializers/discord_bot.rb)
      skip_prefixes = %w[db: assets: tailwindcss: tmp: yarn: webpacker: about middleware notes routes secret spec test guildsync:]
      db_task_running = ARGV.any? { |arg| skip_prefixes.any? { |prefix| arg.to_s.start_with?(prefix) } }
      if !db_task_running && defined?(Rake) && Rake.respond_to?(:application) && Rake.application
        db_task_running = Rake.application.top_level_tasks.any? { |task| skip_prefixes.any? { |prefix| task.to_s.start_with?(prefix) } }
      end

      require_relative "../lib/pricing_plan_initializer"
      require_relative "../lib/game_initializer"
      require_relative "../lib/redis_connection_checker"
      require_relative "../lib/sidekiq_checker"
      require_relative "../lib/postgres_connection_checker"

      # Run startup checks (skip in test environment and during migrations)
      unless Rails.env.test? ||
             (defined?(Rails::Console) && Rails.const_defined?("Console")) ||
             db_task_running
        puts "\n" + "="*60
        puts "  SERVICE STATUS"
        puts "="*60 + "\n"

        results = {}

        # Check database connection
        results[:database] = PostgresConnectionChecker.check!
        puts "="*60

        # Ensure Free pricing plan exists
        results[:pricing_plans] = PricingPlanInitializer.ensure_plans_exist!
        puts "="*60
        
        # Ensure popular games exist (from IGDB)
        results[:games] = GameInitializer.ensure_games_exist!
        puts "="*60

        # Check Redis connection
        results[:redis] = RedisConnectionChecker.check!
        puts "="*60

        # Check Sidekiq availability
        results[:sidekiq] = SidekiqChecker.check!
        puts "="*60

        # Check Discord Bot Token
        if ENV["DISCORD_BOT_TOKEN"].present?
          puts "  ✓ Discord Bot Token: OK"
          results[:discord_bot_token] = true
        else
          puts "  ✗ Discord Bot Token: NOT SET"
          results[:discord_bot_token] = false
        end
        puts "="*60

        # Store results in a constant for summary (will be printed after Discord Bot connects)
        STARTUP_CHECK_RESULTS = results
      end
    end

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Permit YAML column types (serialized metadata / legacy columns).
    config.active_record.yaml_column_permitted_classes = (
      Array(config.active_record.yaml_column_permitted_classes) + [
        Time,
        Date,
        DateTime,
        Symbol,
        BigDecimal,
        ActiveSupport::TimeWithZone,
        ActiveSupport::TimeZone
      ]
    ).uniq

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # Also ignore standalone scripts that don't define classes/modules.
    config.autoload_lib(ignore: %w[assets tasks scripts update_stripe_price_ids.rb])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    # config.api_only = true  # Disabled to support web views for landing page and login

    # Enable sessions and cookies for web views
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
      key: "_guildsync_session",
      same_site: :lax,
      secure: Rails.env.production?,
      httponly: true,
      expire_after: 2.weeks,
      # Host-only cookies in development/test: Safari and some browsers reject a `.localhost`
      # domain derived from `:all`, which breaks session persistence on macOS local dev.
      # Production keeps `:all` for subdomain cookie sharing where needed.
      domain: (Rails.env.test? || Rails.env.development?) ? nil : :all

    # Enable asset pipeline for tailwindcss-rails
    config.assets.enabled = true

    # Add security middleware
    config.middleware.use Rack::Attack
    config.middleware.use SecureHeaders::Middleware
    # Log API request/response metadata with basic redaction.
    require Rails.root.join("app", "middleware", "api_request_response_logging_middleware.rb").to_s
    config.middleware.use ApiRequestResponseLoggingMiddleware
    # Log API failures to dedicated api_failures.txt (require so constant is available at boot)
    require Rails.root.join("app", "middleware", "api_failure_logging_middleware.rb").to_s
    config.middleware.use ApiFailureLoggingMiddleware

    # Internationalization
    config.i18n.load_path += Dir[Rails.root.join('config', 'locales', '**', '*.{rb,yml}')]
    config.i18n.default_locale = :en
    config.i18n.available_locales = [:en, :de, :es, :fr, :it, :ja, :ko, :pt, :ru, :zh]
    config.i18n.fallbacks = true
  end
end
