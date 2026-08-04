# frozen_string_literal: true

# Full service status check including Discord bot gateway connection.
# Used by deploy.sh to verify all services once before asset compilation.
# Run manually: bundle exec rake guildsync:service_status
namespace :guildsync do
  desc "Run full service status check with Discord bot gateway verification"
  task service_status: :environment do
    require_relative "../../lib/pricing_plan_initializer"
    require_relative "../../lib/game_initializer"
    require_relative "../../lib/redis_connection_checker"
    require_relative "../../lib/sidekiq_checker"
    require_relative "../../lib/postgres_connection_checker"

    puts "\n" + "=" * 60
    puts "  SERVICE STATUS"
    puts "=" * 60

    results = {}

    results[:database] = PostgresConnectionChecker.check!
    puts "=" * 60

    results[:pricing_plans] = PricingPlanInitializer.ensure_plans_exist!
    puts "=" * 60

    results[:games] = GameInitializer.ensure_games_exist!
    puts "=" * 60

    results[:redis] = RedisConnectionChecker.check!
    puts "=" * 60

    results[:sidekiq] = SidekiqChecker.check!
    puts "=" * 60

    if ENV["DISCORD_BOT_TOKEN"].present?
      puts "  \u2713 Discord Bot Token: OK"
      results[:discord_bot_token] = true
    else
      puts "  \u26A0 Discord Bot Token: not set (skipping bot gateway check)"
      results[:discord_bot_token] = true
    end
    puts "=" * 60

    # Discord gateway check is optional during deploy (set DEPLOY_SKIP_DISCORD_GATEWAY_CHECK=1).
    discord_bot_success = true
    if ENV["DISCORD_BOT_TOKEN"].present? && ENV["DEPLOY_SKIP_DISCORD_GATEWAY_CHECK"].present?
      puts "  \u26A0 Discord Bot: gateway check skipped (DEPLOY_SKIP_DISCORD_GATEWAY_CHECK)"
    elsif ENV["DISCORD_BOT_TOKEN"].present?
      discord_bot_success = false
      service = nil
      begin
        service = DiscordBotService.new
        service.start
        sleep(1)

        if service.connected?
          puts "  \u2713 Discord Bot: Gateway connected and running"
          puts "  \u2713 Auto-reconnect enabled - bot will stay online"
          discord_bot_success = true
        else
          puts "  \u26A0 Discord Bot: Starting (connection in progress...)"
          puts "  \u2713 Auto-reconnect enabled - bot will connect automatically"
          discord_bot_success = true
        end
      rescue => e
        puts "  \u2717 Discord Bot: FAILED - #{e.message}"
        Rails.logger.error "Service status Discord bot check failed: #{e.message}"
      ensure
        service&.stop
      end
    end
    puts "=" * 60

    results[:discord_bot] = discord_bot_success

    puts "\n" + "-" * 60
    if results.values.all?
      puts "  \u2713 All services ready"
    else
      failed = results.select { |_k, v| !v }.keys
      puts "  \u2717 Issues: #{failed.join(', ')}"
      abort "guildsync:service_status failed: #{failed.join(', ')}"
    end
    puts "=" * 60 + "\n"
  end
end
