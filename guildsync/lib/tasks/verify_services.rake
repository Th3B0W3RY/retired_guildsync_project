# frozen_string_literal: true

# Startup/health verification for critical services. READ-ONLY CHECKS ONLY.
# Logs to GUILDSYNC_LOG_DIR (startup_checks.txt) and Rails.logger.
# Run manually: bundle exec rake guildsync:verify_services
# Can be invoked on server startup (e.g. from a process manager) to log status without modifying anything.
namespace :guildsync do
  desc "Verify critical services (read-only). Logs to startup_checks.txt in GUILDSYNC_LOG_DIR."
  task verify_services: :environment do
    log_name = GuildsyncLoggers.startup_checks
    log_dir = GuildsyncLoggers.log_dir

    GuildsyncLoggers.info(log_name, "VERIFYING CRITICAL SERVICES AT STARTUP...")
    Rails.logger.info "GuildSync startup verification started. Log dir: #{log_dir}"

    results = []

    # 1) Database connection
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      results << { service: "Database", healthy: true, message: "Connected" }
      GuildsyncLoggers.info(log_name, "Database: OK")
    rescue => e
      results << { service: "Database", healthy: false, message: e.message }
      GuildsyncLoggers.error(log_name, "Database: FAILED - #{e.message}")
      Rails.logger.error "Startup check Database failed: #{e.message}"
    end

    # 2) Redis (Sidekiq/cache) - optional in dev, critical in production
    begin
      redis_url = RedisConfig.sidekiq_url
      redis = Redis.new(url: redis_url, timeout: 2)
      redis.ping
      redis.close
      results << { service: "Redis", healthy: true, message: "Connected" }
      GuildsyncLoggers.info(log_name, "Redis: OK")
    rescue => e
      results << { service: "Redis", healthy: false, message: e.message }
      GuildsyncLoggers.error(log_name, "Redis: FAILED - #{e.message}")
      Rails.logger.error "Startup check Redis failed: #{e.message}" if Rails.env.production?
    end

    # 3) Stripe webhook secret (must be set for webhooks to verify)
    begin
      secret_set = ENV["STRIPE_WEBHOOK_SECRET"].present?
      results << { service: "Stripe Webhook Config", healthy: secret_set, message: secret_set ? "STRIPE_WEBHOOK_SECRET set" : "STRIPE_WEBHOOK_SECRET not set" }
      if secret_set
        GuildsyncLoggers.info(log_name, "Stripe Webhook Config: OK")
      else
        GuildsyncLoggers.warn(log_name, "Stripe Webhook Config: STRIPE_WEBHOOK_SECRET not set - webhook signature verification disabled")
      end
    rescue => e
      results << { service: "Stripe Webhook Config", healthy: false, message: e.message }
      GuildsyncLoggers.error(log_name, "Stripe Webhook Config: #{e.message}")
    end

    # 4) Critical models/tables exist (read-only)
    begin
      Subscription.connection
      Subscription.limit(0).to_a
      PricingPlan.limit(0).to_a
      results << { service: "Subscription/PricingPlan tables", healthy: true, message: "Present" }
      GuildsyncLoggers.info(log_name, "Subscription/PricingPlan tables: OK")
    rescue => e
      results << { service: "Subscription/PricingPlan tables", healthy: false, message: e.message }
      GuildsyncLoggers.error(log_name, "Subscription/PricingPlan tables: #{e.message}")
    end

    # 5) OCR/gear tables (read-only)
    begin
      GearSnapshot.limit(0).to_a
      User.limit(0).pluck(:id)
      results << { service: "OCR/Gear tables", healthy: true, message: "Present" }
      GuildsyncLoggers.info(log_name, "OCR/Gear tables: OK")
    rescue => e
      results << { service: "OCR/Gear tables", healthy: false, message: e.message }
      GuildsyncLoggers.error(log_name, "OCR/Gear tables: #{e.message}")
    end

    failed = results.reject { |r| r[:healthy] }
    if failed.any?
      GuildsyncLoggers.warn(log_name, "Startup verification had #{failed.size} issue(s). Manual review may be needed.")
      Rails.logger.warn "GuildSync startup verification: #{failed.size} check(s) failed. See #{log_dir}/startup_checks.txt"
    else
      GuildsyncLoggers.info(log_name, "All startup checks passed.")
      Rails.logger.info "GuildSync startup verification: all checks passed."
    end
  end
end
