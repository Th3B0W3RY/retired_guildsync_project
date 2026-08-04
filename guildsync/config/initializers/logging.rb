require "logging"
require "fileutils"
require_relative "../../lib/guildsync_loggers"
require_relative "../../lib/guildsync_logging/safe_rolling_file"

# All system logs (Rails, Sidekiq, Puma, Discord, and GuildsyncLoggers dedicated files) use this directory.
# Set GUILDSYNC_LOG_DIR in .env or environment so everything goes to the same place.
LOG_DIR = GuildsyncLoggers.log_dir

# Create logs directory if it doesn't exist
FileUtils.mkdir_p(LOG_DIR)

# Configure the logging system
Logging.init

# Create a layout for the log messages
layout = Logging.layouts.pattern(
  pattern: '[%d] %-5l: %m\n',
  date_pattern: '%Y-%m-%d %H:%M:%S'
)

# Create the appender for the main Rails log file
rails_appender = GuildsyncLogging::SafeRollingFile.new(
  'rails.log',
  filename: File.join(LOG_DIR, "#{Rails.env}.log"),
  layout: layout,
  keep: 2, # Keep 2 log files
  age: 'daily',
  truncate: true,
  safe: true # Helps with Windows file locking issues
).build

# Create console appender for STDOUT
console_appender = Logging.appenders.stdout(
  'console',
  layout: layout
)

# Create the main Rails logger
rails_logger = Logging.logger['Rails']
rails_logger.add_appenders(rails_appender, console_appender)
rails_logger.level = if Rails.env.production?
  :info
elsif Rails.env.development?
  :debug
elsif Rails.env.test?
  # Default to warn in test, but allow override via environment variable
  # or config.log_level in environments/test.rb
  if ENV["DEBUG"] == "1" || ENV["LOG_LEVEL"] == "debug"
    :debug
  else
    :warn
  end
else
  :warn
end

# Configure Rails to use our logger directly
Rails.logger = rails_logger

# Define dummy broadcast_to method to satisfy Rails 8
class << Rails.logger
  def broadcast_to(_console)
    # No-op since we're handling output through logging gem
  end
end

# Configure Sidekiq logger to also use the same location
# Note: Sidekiq 7.x doesn't support direct logger assignment via Sidekiq.logger=
# We'll create the logger here and configure it in config/initializers/sidekiq.rb
# Skip if Sidekiq is not available
begin
  if defined?(Sidekiq)
    sidekiq_appender = GuildsyncLogging::SafeRollingFile.new(
      'sidekiq.log',
      filename: File.join(LOG_DIR, "sidekiq_logs.txt"),
      layout: layout,
      keep: 2,
      age: 'daily',
      truncate: true,
      safe: true
    ).build
    
    sidekiq_logger = Logging.logger['Sidekiq']
    sidekiq_logger.add_appenders(sidekiq_appender, console_appender)
    sidekiq_logger.level = Rails.env.development? ? :debug : :info
    
    # Store the logger in a constant so it can be accessed from sidekiq.rb
    SIDEKIQ_LOGGER = sidekiq_logger
  end
rescue => e
  # If Sidekiq logger setup fails, just log a warning and continue
  # The app will still work, Sidekiq will just use its default logger
  Rails.logger.warn "Could not configure Sidekiq logger: #{e.message}" if defined?(Rails) && Rails.respond_to?(:logger)
end

# Configure Puma logger (if available)
if defined?(Puma)
  puma_appender = GuildsyncLogging::SafeRollingFile.new(
    'puma.log',
    filename: File.join(LOG_DIR, "puma_logs.txt"),
    layout: layout,
    keep: 2,
    age: 'daily',
    truncate: true,
    safe: true
  ).build
  
  puma_logger = Logging.logger['Puma']
  puma_logger.add_appenders(puma_appender, console_appender)
  puma_logger.level = Rails.env.development? ? :debug : :info
end

# Configure Discord logger - separate log file for Discord interactions
discord_appender = GuildsyncLogging::SafeRollingFile.new(
  'discord.log',
  filename: File.join(LOG_DIR, "discord.log"),
  layout: layout,
  keep: 7, # Keep 7 days of Discord logs (more than main logs for debugging)
  age: 'daily',
  truncate: true,
  safe: true
).build

discord_logger = Logging.logger['Discord']
discord_logger.add_appenders(discord_appender, console_appender)
discord_logger.level = Rails.env.development? ? :debug : :info

# Forward Discord errors/warnings to dedicated discord_failures.txt (90-day rotation)
module DiscordLoggerForwardToFile
  %i[error warn fatal].each do |level|
    define_method(level) do |*args, &block|
      result = super(*args, &block)
      msg = block ? block.call : args.first
      msg = msg.to_s.strip
      GuildsyncLoggers.public_send(level, GuildsyncLoggers.discord_failures, msg) if msg.present? && defined?(GuildsyncLoggers)
      result
    end
  end
end
discord_logger.extend(DiscordLoggerForwardToFile)

# Make Discord logger available globally
DiscordLogger = discord_logger

# Redirect all standard loggers to our custom location
# This ensures ALL logs go to ~/GuildSync/logs/

# Override ActiveSupport::Logger if it tries to use default location
module ActiveSupport
  class Logger
    alias_method :original_initialize, :initialize
    
    def initialize(*args)
      # If no log device specified, use our custom location
      if args.empty? || args.first.nil?
        log_file = File.join(LOG_DIR, "#{Rails.env}.log")
        args = [File.open(log_file, 'a')]
      end
      original_initialize(*args)
    end
  end
end

# Ensure ActionController::Base uses our logger
if defined?(ActionController) && ActionController::Base.respond_to?(:logger=)
  ActionController::Base.logger = Rails.logger
end

# Ensure ActiveRecord::Base uses our logger
if defined?(ActiveRecord) && ActiveRecord::Base.respond_to?(:logger=)
  ActiveRecord::Base.logger = Rails.logger
end

# Ensure ActionMailer uses our logger
if defined?(ActionMailer) && ActionMailer::Base.respond_to?(:logger=)
  ActionMailer::Base.logger = Rails.logger
end

# Ensure ActionCable uses our logger
if defined?(ActionCable) && ActionCable.server.respond_to?(:logger=)
  ActionCable.server.logger = Rails.logger
end

# Log unhandled exceptions
Rails.application.config.exceptions_app = ->(env) do
  request = ActionDispatch::Request.new(env)
  Rails.logger.error("Unhandled exception: #{request.path}")
  Rails.logger.error(env['action_dispatch.exception'].inspect)
  Rails.logger.error(env['action_dispatch.exception'].backtrace.join("\n"))
  ActionDispatch::PublicExceptions.new(Rails.public_path).call(env)
end

# Log that logging system is initialized (only to file, not console)
Rails.logger.info "Logging system initialized - All logs written to: #{LOG_DIR}"

