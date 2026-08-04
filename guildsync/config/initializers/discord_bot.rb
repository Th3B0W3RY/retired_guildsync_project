# Initialize Discord Bot on Rails startup
# This uses Gateway (WebSocket) instead of HTTP interactions endpoint
# No ngrok or tunneling required!

# Fix SSL certificate verification for macOS
# This is required for WebSocket connections to Discord Gateway
# The issue is OpenSSL can't verify Certificate Revocation Lists (CRL) on macOS
# discordrb has built-in support for disabling SSL verification via environment variable
if RUBY_PLATFORM.include?('darwin') && Rails.env.development?
  # Set environment variable that discordrb checks to disable SSL verification
  ENV['DISCORDRB_SSL_VERIFY_NONE'] = '1'
  
  Rails.logger.warn "⚠️  Discord Bot: SSL verification DISABLED for development (CRL workaround)"
  Rails.logger.warn "⚠️  Set via DISCORDRB_SSL_VERIFY_NONE=1"
  Rails.logger.warn "⚠️  This should NEVER be enabled in production!"
end

# Global accessor for Discord bot service
def discord_bot_service
  @discord_bot_service
end

if Rails.env.development? || Rails.env.production?
  # Skip bot for non-web rake tasks. The bot should only run inside Puma (or an
  # explicit service-check task). This prevents unnecessary Discord gateway
  # connections during migrations, asset compilation, tailwind builds, etc.
  SKIP_BOT_TASK_PREFIXES = %w[db: assets: tailwindcss: tmp: yarn: webpacker: about middleware notes routes secret spec test guildsync:].freeze
  rake_task_running = ARGV.any? { |arg| SKIP_BOT_TASK_PREFIXES.any? { |prefix| arg.to_s.start_with?(prefix) } }
  if !rake_task_running && defined?(Rake) && Rake.respond_to?(:application) && Rake.application
    rake_task_running = Rake.application.top_level_tasks.any? { |task| SKIP_BOT_TASK_PREFIXES.any? { |prefix| task.to_s.start_with?(prefix) } }
  end

  Rails.application.config.after_initialize do
    if rake_task_running
      Rails.logger.info "Skipping Discord bot initialization for rake task"
      next
    end

    # Skip in Sidekiq worker processes — the bot only runs in the web process (Puma)
    if defined?(Sidekiq) && Sidekiq.server?
      Rails.logger.info "Skipping Discord bot initialization in Sidekiq worker"
      next
    end

    # Skip if summary already printed
    next if defined?(STARTUP_SUMMARY_PRINTED)
    
    discord_bot_success = false
    
    if ENV["DISCORD_BOT_TOKEN"].present?
      begin
        @discord_bot_service = DiscordBotService.new
        @discord_bot_service.start
        
        # Give bot a moment to connect
        sleep(1)
        
        # Check if bot is actually connected
        if @discord_bot_service.connected?
          puts "  ✓ Discord Bot: Gateway connected and running"
          puts "  ✓ Auto-reconnect enabled - bot will stay online"
          puts "="*60
          discord_bot_success = true
        else
          puts "  ⚠ Discord Bot: Starting (connection in progress...)"
          puts "  ✓ Auto-reconnect enabled - bot will connect automatically"
          puts "="*60
          discord_bot_success = true # Still consider it success since it will connect
        end
      rescue => e
        puts "  ✗ Discord Bot: FAILED - #{e.message}"
        puts "="*60
        discord_bot_success = false
        
        Rails.logger.error "Failed to initialize Discord bot: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
    else
      # No Discord Bot Token
      discord_bot_success = false
    end
    
    # Print summary once after all checks complete
    if defined?(STARTUP_CHECK_RESULTS)
      results = STARTUP_CHECK_RESULTS.merge(discord_bot: discord_bot_success)
      
      puts "\n" + "-"*60
      all_passed = results.values.all?
      if all_passed
        puts "  ✓ All services ready"
      else
        failed = results.select { |k, v| !v }.keys
        puts "  ✗ Issues: #{failed.join(', ')}"
      end
      puts "="*60 + "\n"
      
      # Mark summary as printed to prevent duplicates
      STARTUP_SUMMARY_PRINTED = true
    end
  end

  # Cleanup on shutdown
  at_exit do
    @discord_bot_service&.stop
  end
end

