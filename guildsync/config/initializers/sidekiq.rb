# frozen_string_literal: true

# Sidekiq Configuration
# Sidekiq is a background job processor that uses Redis
#
# Environment Variables:
# - REDIS_URL: Full Redis connection URL
# - REDIS_SIDEKIQ_DB: Redis database number for Sidekiq (default: 1)
#
# Start Sidekiq with: bundle exec sidekiq

require "sidekiq/web"
require_relative "redis"

Sidekiq.configure_server do |config|
  # Use separate Redis database for Sidekiq to avoid conflicts with cache
  # Note: Sidekiq 7+ no longer supports namespace option
  sidekiq_url = RedisConfig.sidekiq_url
  config.redis = {
    url: sidekiq_url,
    size: ENV.fetch("SIDEKIQ_CONCURRENCY", "10").to_i + 5
  }.merge(RedisConfig.ssl_options_for(sidekiq_url))

  # Configure custom logger if available (set up in logging.rb)
  if defined?(SIDEKIQ_LOGGER)
    begin
      # Sidekiq 7.x may support logger configuration via config
      config.logger = SIDEKIQ_LOGGER if config.respond_to?(:logger=)
    rescue => e
      Rails.logger.warn "Could not configure Sidekiq logger: #{e.message}"
    end
  end

  # Error handling with safe navigation
  config.death_handlers << ->(job, ex) do
    Sidekiq.logger.error("Job #{job['class']} failed permanently: #{ex&.message}")
  end
end

Sidekiq.configure_client do |config|
  # Note: Sidekiq 7+ no longer supports namespace option
  sidekiq_url = RedisConfig.sidekiq_url
  config.redis = {
    url: sidekiq_url,
    size: ENV.fetch("SIDEKIQ_CLIENT_POOL_SIZE", "5").to_i
  }.merge(RedisConfig.ssl_options_for(sidekiq_url))

  # Configure custom logger if available (set up in logging.rb)
  if defined?(SIDEKIQ_LOGGER)
    begin
      config.logger = SIDEKIQ_LOGGER if config.respond_to?(:logger=)
    rescue => e
      Rails.logger.warn "Could not configure Sidekiq client logger: #{e.message}"
    end
  end
end

# Sidekiq Web UI Configuration
# Access at: /sidekiq (protected by admin authentication)
# Note: Sidekiq 7+ handles Web UI configuration in routes.rb, not here
# The require 'sidekiq/web' is already in routes.rb

# Admin authentication middleware for Sidekiq
class SidekiqAdminAuth
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    # Use Rails session middleware to access session
    # The session should already be available in env if Rails middleware ran
    session = env["rack.session"] || {}

    unless session && session["admin_authenticated"] == true
      return [ 302, { "Location" => "/admin/login", "Content-Type" => "text/html" }, [ "Redirecting to admin login..." ] ]
    end

    @app.call(env)
  end
end

# Add session middleware before auth check
sidekiq_session_secret = Rails.application.secret_key_base
if sidekiq_session_secret.bytesize < 64
  multiplier = (64.0 / sidekiq_session_secret.bytesize).ceil
  sidekiq_session_secret = (sidekiq_session_secret * multiplier).byteslice(0, 64)
end

Sidekiq::Web.use Rack::Session::Cookie,
  key: "_guildsync_session",
  secret: sidekiq_session_secret,
  same_site: :lax,
  secure: Rails.env.production?

Sidekiq::Web.use SidekiqAdminAuth

# ============================================================================
# PERIODIC JOB SCHEDULING
# ============================================================================
# All periodic background jobs are scheduled here for centralized management.
#
# NOTE: Currently using Thread.new loops for scheduling. For production,
# consider using sidekiq-cron gem for better job management, history tracking,
# and manual triggering capabilities:
#   gem 'sidekiq-cron'
#
# Future: Admin console integration
#   - Job run history and statistics
#   - Manual job triggering
#   - Job status monitoring
#   - Schedule modification
# ============================================================================

Sidekiq.configure_server do |config|
  config.on(:startup) do
    # ========================================================================
    # DISCORD JOBS
    # ========================================================================

    # Schedule Discord bot presence check every 10 minutes
    Thread.new do
      loop do
        sleep 600 # 10 minutes
        begin
          DiscordBotPresenceCheckJob.perform_later
        rescue => e
          Rails.logger.error "Failed to enqueue DiscordBotPresenceCheckJob: #{e.message}"
        end
      end
    end

    # Schedule Discord role refresh every 30 minutes
    Thread.new do
      loop do
        sleep 1800 # 30 minutes
        begin
          DiscordRoleRefreshJob.perform_async
        rescue => e
          Rails.logger.error "Failed to enqueue DiscordRoleRefreshJob: #{e.message}"
        end
      end
    end

    # ========================================================================
    # GAME MANAGEMENT JOBS
    # ========================================================================

    # Schedule IGDB game sync daily at 2 AM
    Thread.new do
      loop do
        # Calculate seconds until next 2 AM
        now = Time.current
        target_time = now.beginning_of_day + 2.hours
        target_time += 1.day if now >= target_time

        sleep_seconds = (target_time - now).to_i
        Rails.logger.info "IGDB sync scheduled for #{target_time}. Sleeping #{sleep_seconds} seconds..."
        sleep(sleep_seconds)

        begin
          SyncGamesWithIgdbJob.perform_later
          Rails.logger.info "IGDB sync job enqueued"
        rescue => e
          Rails.logger.error "Failed to enqueue SyncGamesWithIgdbJob: #{e.message}"
        end

        # After running, wait until next day
        sleep(86400) # 24 hours
      end
    end

    # ========================================================================
    # BILLING / TRIAL MANAGEMENT JOBS
    # ========================================================================

    # Schedule ExpireTrialsJob daily at 3 AM server time
    Thread.new do
      loop do
        now = Time.current
        target = now.beginning_of_day + 3.hours # 3 AM
        target += 1.day if now >= target
        sleep_seconds = (target - now).to_i
        Rails.logger.info "ExpireTrialsJob scheduled for #{target}. Sleeping #{sleep_seconds} seconds..."
        sleep(sleep_seconds)

        begin
          ExpireTrialsJob.perform_async
          Rails.logger.info "ExpireTrialsJob enqueued"
        rescue => e
          Rails.logger.error "Failed to enqueue ExpireTrialsJob: #{e.message}"
        end

        sleep(86400) # 24 hours until next run
      end
    end

    # ========================================================================
    # MEMBERS GEAR JOBS
    # ========================================================================

    # Schedule outdated gear snapshots check every 30 minutes
    # This job checks for outdated gear snapshots and can be extended
    # to send notifications or generate reports
    Thread.new do
      loop do
        sleep 1800 # 30 minutes
        begin
          MarkOutdatedGearSnapshotsJob.perform_later
        rescue => e
          Rails.logger.error "Failed to enqueue MarkOutdatedGearSnapshotsJob: #{e.message}"
        end
      end
    end

    # ========================================================================
    # ACTIVITY FEED: prune logs older than 3 months (run daily)
    # ========================================================================
    Thread.new do
      loop do
        now = Time.current
        target = now.beginning_of_day + 3.hours # 3 AM
        target += 1.day if now >= target
        sleep_seconds = (target - now).to_i
        Rails.logger.info "GuildActivityLogPruneJob scheduled for #{target}. Sleeping #{sleep_seconds} seconds..."
        sleep(sleep_seconds)
        begin
          GuildActivityLogPruneJob.perform_async
          AllianceActivityLogPruneJob.perform_async
          PurgeExpiredGearSnapshotsJob.perform_later
          PurgeExpiredSoftDeletedRecordsJob.perform_async
          Rails.logger.info "GuildActivityLogPruneJob, AllianceActivityLogPruneJob, PurgeExpiredGearSnapshotsJob, and PurgeExpiredSoftDeletedRecordsJob enqueued"
        rescue => e
          Rails.logger.error "Failed to enqueue GuildActivityLogPruneJob: #{e.message}"
        end
        sleep(86400) # 24 hours until next run
      end
    end

    # ========================================================================
    # ARCHIVED GUILDS: purge records past scheduled_purge_at (daily at 5 AM)
    # ========================================================================
    Thread.new do
      loop do
        now = Time.current
        target = now.beginning_of_day + 5.hours # 5 AM
        target += 1.day if now >= target
        sleep_seconds = (target - now).to_i
        Rails.logger.info "PurgeArchivedGuildsJob scheduled for #{target}. Sleeping #{sleep_seconds} seconds..."
        sleep(sleep_seconds)
        begin
          PurgeArchivedGuildsJob.perform_later
          Rails.logger.info "PurgeArchivedGuildsJob enqueued"
        rescue => e
          Rails.logger.error "Failed to enqueue PurgeArchivedGuildsJob: #{e.message}"
        end
        sleep(86400)
      end
    end

    # ========================================================================
    # S3 VERIFICATION: run daily to confirm S3 storage is working (logs to s3_verification.txt / s3_errors.txt)
    # ========================================================================
    Thread.new do
      loop do
        now = Time.current
        target = now.beginning_of_day + 4.hours # 4 AM
        target += 1.day if now >= target
        sleep_seconds = (target - now).to_i
        sleep(sleep_seconds)
        begin
          S3VerificationJob.perform_async
        rescue => e
          Rails.logger.error "Failed to enqueue S3VerificationJob: #{e.message}"
        end
        sleep(86400)
      end
    end

    # ========================================================================
    # ERROR BATCH REPORT: bundle non-immediate errors and deliver to Discord.
    # Cadence is read from SiteSetting.error_batch_cadence_hours (default 24h)
    # and can be changed live in the admin console. The loop checks every hour
    # whether a new report is due based on when the last one was created.
    # ========================================================================
    Thread.new do
      sleep(300) # 5 minutes after startup before first check
      loop do
        begin
          cadence_hours = SiteSetting.error_batch_cadence_hours
          last_report   = ErrorBatchReport.order(created_at: :desc).first
          last_run      = last_report&.created_at || (Time.current - cadence_hours.hours - 1.second)
          if Time.current - last_run >= cadence_hours.hours
            ErrorBatchReportJob.perform_later("scheduled")
            Rails.logger.info "ErrorBatchReportJob enqueued (cadence: #{cadence_hours}h)"
          end
        rescue => e
          Rails.logger.error "Failed to check/enqueue ErrorBatchReportJob: #{e.message}"
        end
        sleep(3600) # re-check every hour
      end
    end

    # ========================================================================
    # ERROR LOG CLEANUP: delete resolved error logs older than 30 days (daily at 4:30 AM)
    # ========================================================================
    Thread.new do
      loop do
        now = Time.current
        target = now.beginning_of_day + 4.hours + 30.minutes # 4:30 AM
        target += 1.day if now >= target
        sleep_seconds = (target - now).to_i
        sleep(sleep_seconds)
        begin
          CleanupErrorLogsJob.perform_later
          Rails.logger.info "CleanupErrorLogsJob enqueued"
        rescue => e
          Rails.logger.error "Failed to enqueue CleanupErrorLogsJob: #{e.message}"
        end
        sleep(86400)
      end
    end

    # ========================================================================
    # LOG ROTATION: delete dedicated .txt log files every 90 days (recreated on next write)
    # ========================================================================
    Thread.new do
      loop do
        sleep(90 * 86400) # 90 days
        begin
          LogRotationJob.perform_async
          Rails.logger.info "LogRotationJob enqueued (90-day rotation)"
        rescue => e
          Rails.logger.error "Failed to enqueue LogRotationJob: #{e.message}"
        end
      end
    end

    # ========================================================================
    # CRITICAL JOBS MONITORING: run every 6 hours (read-only checks, logs to job_monitoring.txt)
    # ========================================================================
    Thread.new do
      sleep(60)
      loop do
        begin
          CriticalJobsMonitorJob.perform_async
          Rails.logger.info "CriticalJobsMonitorJob enqueued (6-hourly monitoring)"
        rescue => e
          Rails.logger.error "Failed to enqueue CriticalJobsMonitorJob: #{e.message}"
        end
        sleep(6 * 3600)
      end
    end

    # ========================================================================
    # CONTENT MODERATION HEALTH CHECK: run every 6 hours
    # ========================================================================
    Thread.new do
      sleep(120) # 2 minutes after start
      loop do
        begin
          ContentModerationHealthCheckJob.perform_async
          Rails.logger.info "ContentModerationHealthCheckJob enqueued (6-hourly)"
        rescue => e
          Rails.logger.error "Failed to enqueue ContentModerationHealthCheckJob: #{e.message}"
        end
        sleep(6 * 3600)
      end
    end

    # ========================================================================
    # IP MEMBERSHIP COMPLIANCE AUDIT: run 5x/day (~every 4.8 hours)
    # ========================================================================
    Thread.new do
      sleep(240) # 4 minutes after start
      loop do
        begin
          IpMembershipAuditJob.perform_async
          Rails.logger.info "IpMembershipAuditJob enqueued (5x/day)"
        rescue => e
          Rails.logger.error "Failed to enqueue IpMembershipAuditJob: #{e.message}"
        end
        sleep((24.hours / 5).to_i)
      end
    end

    # ========================================================================
    # PROFANITY LIST UPDATE: fetch from internet sources every 6 hours
    # ========================================================================
    Thread.new do
      sleep(180) # 3 minutes after start
      loop do
        begin
          ProfanityListUpdateJob.perform_async
          Rails.logger.info "ProfanityListUpdateJob enqueued (6-hourly)"
        rescue => e
          Rails.logger.error "Failed to enqueue ProfanityListUpdateJob: #{e.message}"
        end
        sleep(6 * 3600)
      end
    end

    # ========================================================================
    # DATABASE BACKUP TO S3: monthly 1st @ 6 AM when DATABASE_BACKUP_TO_S3_ENABLED=1 at Sidekiq boot
    # ========================================================================
    if ENV["DATABASE_BACKUP_TO_S3_ENABLED"].to_s == "1"
      Thread.new do
        loop do
          now = Time.current
          target = now.beginning_of_month.change(hour: 6)
          target += 1.month if now >= target
          sleep_seconds = (target - now).to_i
          Rails.logger.info "DatabaseBackupToS3Job scheduled for #{target}. Sleeping #{sleep_seconds} seconds..."
          sleep(sleep_seconds)
          begin
            DatabaseBackupToS3Job.perform_later
            Rails.logger.info "DatabaseBackupToS3Job enqueued"
          rescue => e
            Rails.logger.error "Failed to enqueue DatabaseBackupToS3Job: #{e.message}"
          end
        end
      end
    end

    # ========================================================================
    # CONFIG SNAPSHOT TO S3: monthly 1st @ 6:30 AM when CONFIG_SNAPSHOT_TO_S3_ENABLED=1 at Sidekiq boot
    # ========================================================================
    if ENV["CONFIG_SNAPSHOT_TO_S3_ENABLED"].to_s == "1"
      Thread.new do
        loop do
          now = Time.current
          target = now.beginning_of_month.change(hour: 6, min: 30)
          target += 1.month if now >= target
          sleep_seconds = (target - now).to_i
          Rails.logger.info "ConfigSnapshotToS3Job scheduled for #{target}. Sleeping #{sleep_seconds} seconds..."
          sleep(sleep_seconds)
          begin
            ConfigSnapshotToS3Job.perform_later
            Rails.logger.info "ConfigSnapshotToS3Job enqueued"
          rescue => e
            Rails.logger.error "Failed to enqueue ConfigSnapshotToS3Job: #{e.message}"
          end
        end
      end
    end

    # ========================================================================
    # FONT AWESOME FREE ICON CATALOG: weekly sync (Sunday 02:30 America/Denver)
    # ========================================================================
    Thread.new do
      loop do
        begin
          tz = ActiveSupport::TimeZone["America/Denver"]
          now = tz.now
          target = nil
          (0..20).each do |i|
            d = now.to_date + i
            next unless d.wday == 0

            candidate = begin
              tz.local(d.year, d.month, d.day, 2, 30, 0)
            rescue TZInfo::PeriodNotFound, TZInfo::AmbiguousTime => e
              fallback = tz.local(d.year, d.month, d.day, 3, 0, 0)
              Rails.logger.warn(
                "FontawesomeFreeIconsSyncJob: #{e.class} for Sunday 02:30 America/Denver on #{d}; " \
                "falling back to #{fallback.iso8601}"
              )
              fallback
            end
            next unless candidate > now

            target = candidate
            break
          end
          if target.nil?
            Rails.logger.error "FontawesomeFreeIconsSyncJob: could not compute next Sunday 02:30 America/Denver"
            sleep(3600)
            next
          end
          sleep_seconds = (target - now).to_i
          Rails.logger.info "FontawesomeFreeIconsSyncJob scheduled for #{target.iso8601}. Sleeping #{sleep_seconds}s..."
          sleep(sleep_seconds)
          begin
            FontawesomeFreeIconsSyncJob.perform_later
            Rails.logger.info "FontawesomeFreeIconsSyncJob enqueued (weekly Font Awesome Free catalog sync)"
          rescue => e
            Rails.logger.error "Failed to enqueue FontawesomeFreeIconsSyncJob: #{e.message}"
          end
        rescue => e
          Rails.logger.error "FontawesomeFreeIconsSyncJob scheduler loop failed: #{e.class}: #{e.message}"
          sleep(3600)
        end
      end
    end
  end
end
