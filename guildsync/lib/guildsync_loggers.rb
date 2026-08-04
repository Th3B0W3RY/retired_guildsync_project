# frozen_string_literal: true

# Dedicated log files for GuildSync (Stripe webhooks, API failures, S3, Discord, security audit, etc.).
# All system logs use the directory from ENV["GUILDSYNC_LOG_DIR"] when set (e.g. in .env).
# Set GUILDSYNC_LOG_DIR in .env or your environment so all system logging uses that path.
# Each file is appended to; a 90-day rotation job deletes these files so they are recreated on next write.
# We open-append-close per write so that after rotation the next write creates a new file.
module GuildsyncLoggers
  LOG_ROTATION_DAYS = 90

  # Filenames (without path) for 90-day rotation job
  DEDICATED_LOG_FILES = %w[
    postgres_logs.txt
    redis_logs.txt
    sidekiq_logs.txt
    puma_logs.txt
    s3_errors.txt
    s3_verification.txt
    stripe_webhook_errors.txt
    api_failures.txt
    discord_event_failures.txt
    discord_bot_failures.txt
    discord_failures.txt
    system_warnings.txt
    security_audit.txt
    startup_checks.txt
    job_monitoring.txt
    moderation_health.txt
  ].freeze

  class << self
    def log_dir
      @log_dir ||= begin
        if ENV["GUILDSYNC_LOG_DIR"].present?
          ENV["GUILDSYNC_LOG_DIR"].to_s
        elsif defined?(Rails) && Rails.env.test?
          Rails.root.join("tmp", "logs").to_s
        elsif defined?(Rails) && Rails.env.production?
          Rails.root.join("log").to_s
        elsif Gem.win_platform?
          File.join(ENV["LOCALAPPDATA"] || Dir.home, "GuildSync", "logs")
        else
          File.join(Dir.home, "GuildSync", "logs")
        end.tap { |d| FileUtils.mkdir_p(d) }
      end
    end

    def path(name)
      name = "#{name}.txt" unless name.to_s.end_with?(".txt")
      File.join(log_dir, name)
    end

    # Append one line to a dedicated log file. Thread-safe via mutex per file.
    # log_name can be "s3_errors" or "s3_errors.txt"
    def write(log_name, level, message)
      base = log_name.to_s.end_with?(".txt") ? log_name : "#{log_name}.txt"
      return unless DEDICATED_LOG_FILES.include?(base)

      mutex_for(base).synchronize do
        file_path = path(base)
        File.open(file_path, "a") do |f|
          f.puts "[#{Time.current.utc.iso8601}] #{level.to_s.upcase}: #{message}"
          f.flush
        end
      end
    rescue => e
      # Fallback to Rails logger so we don't lose the message
      Rails.logger.warn("GuildsyncLoggers.write(#{log_name}) failed: #{e.message}") if defined?(Rails) && Rails.respond_to?(:logger)
    end

    def error(log_name, message)
      write(log_name, :error, message)
    end

    def warn(log_name, message)
      write(log_name, :warn, message)
    end

    def info(log_name, message)
      write(log_name, :info, message)
    end

    # Log an exception with backtrace and context (for errors/warnings).
    def log_exception(log_name, exception, context = {})
      lines = [
        "Exception: #{exception.class} - #{exception.message}",
        "Backtrace: #{exception.backtrace&.first(15)&.join(' | ')}",
        context.map { |k, v| "#{k}: #{v}" }.join(", ")
      ].reject(&:blank?)
      error(log_name, lines.join(" | "))
    end

    # Convenience: return base name for use with error/warn/info (e.g. GuildsyncLoggers.error(GuildsyncLoggers.s3_errors, "msg"))
    %w[
      postgres_logs redis_logs sidekiq_logs puma_logs s3_errors s3_verification
      stripe_webhook_errors api_failures discord_event_failures discord_bot_failures
      discord_failures system_warnings security_audit startup_checks job_monitoring
    ].each do |name|
      define_method(name) { name }
    end

    private

    def mutex_for(log_name)
      @mutexes ||= {}
      @mutexes[log_name] ||= Mutex.new
    end
  end
end
