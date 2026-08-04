# frozen_string_literal: true

require "fileutils"

module GuildsyncLogging
  # Builds a `logging` gem rolling_file appender that survives the daily-roll race that
  # happens when several processes (Puma, Sidekiq, a rake task) open the same log file at
  # a date boundary. The gem rolls by copying `file` to `file._copy_` and then renaming
  # that copy to `file.YYYYMMDD`; a concurrent roller can remove `_copy_` first, raising
  # Errno::ENOENT during appender initialization (the failure seen on deploy).
  #
  # Defense in depth alongside running boot-time rake tasks while services are stopped:
  # ensure the target dir/file exist, retry the build once, and finally fall back to a
  # plain (non-rolling) file appender so application boot never fails because of rotation.
  class SafeRollingFile
    def initialize(name, filename:, retries: 1, **options)
      @name = name
      @filename = filename
      @retries = retries
      @options = options
    end

    def build
      ensure_target!
      attempts = 0
      begin
        Logging.appenders.rolling_file(@name, filename: @filename, **@options)
      rescue Errno::ENOENT => e
        attempts += 1
        if attempts <= @retries
          ensure_target!
          retry
        end
        warn_fallback(e)
        Logging.appenders.file(@name, filename: @filename, layout: @options[:layout])
      end
    end

    private

    def ensure_target!
      FileUtils.mkdir_p(File.dirname(@filename))
      FileUtils.touch(@filename) unless File.exist?(@filename)
    end

    def warn_fallback(error)
      message = "[logging] rolling_file '#{@name}' failed (#{error.class}: #{error.message}); " \
                "using non-rolling file appender for this process (NO rotation until restart)"
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        warn(message)
      end
      # Durable ops signal independent of the logger we just failed to build, so a
      # degraded (non-rotating) appender does not go unnoticed.
      GuildsyncLoggers.warn(GuildsyncLoggers.system_warnings, message) if defined?(GuildsyncLoggers)
    rescue StandardError
      # Never let logging-about-logging break boot.
      nil
    end
  end
end
