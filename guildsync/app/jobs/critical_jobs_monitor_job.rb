# frozen_string_literal: true

# MONITORING ONLY - does not modify any jobs or data.
# Runs every 6 hours to verify critical systems are reachable and queues are processing.
# Logs to GUILDSYNC_LOG_DIR (job_monitoring.txt) and Rails.logger.
# Additive: does not replace or change existing job logic.
class CriticalJobsMonitorJob
  include Sidekiq::Worker

  sidekiq_options retry: 2, queue: :default

  JOB_MONITORING_LOG = "job_monitoring"
  QUEUE_BACKLOG_ALERT = 500
  QUEUE_BACKLOG_WARN = 200

  def perform
    log(JOB_MONITORING_LOG, "info", "RUNNING CRITICAL JOB MONITORING CHECK...")
    Rails.logger.info "CriticalJobsMonitorJob: starting read-only monitoring check"

    issues = []

    # 1) Database - read only
    check_database(issues)

    # 2) Redis - read only
    check_redis(issues)

    # 3) Sidekiq queue depth - read only (does not enqueue or process)
    check_sidekiq_queues(issues)

    if issues.any?
      issues.each do |msg|
        log(JOB_MONITORING_LOG, "error", msg)
        Rails.logger.error "CriticalJobsMonitorJob: #{msg}"
      end
      log(JOB_MONITORING_LOG, "warn", "MONITORING FOUND #{issues.size} ISSUE(S). Manual review may be needed. No auto-recovery performed.")
    else
      log(JOB_MONITORING_LOG, "info", "All critical job checks passed.")
      Rails.logger.info "CriticalJobsMonitorJob: all checks passed"
    end
  end

  private

  def check_database(issues)
    ActiveRecord::Base.connection.execute("SELECT 1")
    log(JOB_MONITORING_LOG, "info", "Database: OK")
  rescue => e
    issues << "Database check failed: #{e.message}"
    log(JOB_MONITORING_LOG, "error", "Database: FAILED - #{e.message}")
  end

  def check_redis(issues)
    Sidekiq.redis { |c| c.ping }
    log(JOB_MONITORING_LOG, "info", "Redis: OK")
  rescue => e
    issues << "Redis check failed: #{e.message}"
    log(JOB_MONITORING_LOG, "error", "Redis: FAILED - #{e.message}")
  end

  def check_sidekiq_queues(issues)
    return unless defined?(Sidekiq::Stats)

    stats = Sidekiq::Stats.new
    enqueued = stats.enqueued
    processed = stats.processed
    failed = stats.failed

    log(JOB_MONITORING_LOG, "info", "Sidekiq enqueued=#{enqueued} processed=#{processed} failed=#{failed}")

    if enqueued > QUEUE_BACKLOG_ALERT
      issues << "Sidekiq queue backlog CRITICAL: #{enqueued} jobs enqueued (alert threshold #{QUEUE_BACKLOG_ALERT})"
      log(JOB_MONITORING_LOG, "error", "Sidekiq backlog: #{enqueued} jobs")
    elsif enqueued > QUEUE_BACKLOG_WARN
      log(JOB_MONITORING_LOG, "warn", "Sidekiq queue building: #{enqueued} jobs enqueued")
    end

    # Optional: log failed count for visibility (no auto-retry)
    log(JOB_MONITORING_LOG, "info", "Sidekiq failed count: #{failed}") if failed > 0
  rescue => e
    issues << "Sidekiq stats check failed: #{e.message}"
    log(JOB_MONITORING_LOG, "error", "Sidekiq check: #{e.message}")
  end

  def log(log_name, level, message)
    GuildsyncLoggers.public_send(level, log_name, message)
  end
end
