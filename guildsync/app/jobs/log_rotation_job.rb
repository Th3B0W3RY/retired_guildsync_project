# frozen_string_literal: true

# Deletes dedicated log files so they are recreated on next write (90-day rotation).
# Run every 90 days via Sidekiq scheduler so logs don't grow indefinitely.
class LogRotationJob
  include Sidekiq::Worker

  def perform
    dir = GuildsyncLoggers.log_dir
    GuildsyncLoggers::DEDICATED_LOG_FILES.each do |filename|
      path = File.join(dir, filename)
      next unless File.file?(path)

      File.delete(path)
      Rails.logger.info("LogRotationJob: deleted #{path}")
    rescue => e
      Rails.logger.warn("LogRotationJob: could not delete #{path}: #{e.message}")
    end
  end
end
