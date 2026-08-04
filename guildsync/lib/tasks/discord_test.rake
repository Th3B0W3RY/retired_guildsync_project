namespace :discord do
  desc "Test Discord bot connection and initialization"
  task :test => :environment do
    puts "=" * 80
    puts "Discord Bot Connection Test"
    puts "=" * 80
    puts
    
    # Check environment variable
    if ENV["DISCORD_BOT_TOKEN"].present?
      puts "✅ DISCORD_BOT_TOKEN is set"
    else
      puts "❌ DISCORD_BOT_TOKEN is NOT set"
      puts "   Set it in your .env file: DISCORD_BOT_TOKEN=your_token_here"
      exit 1
    end
    
    puts
    
    # Test initialization
    puts "Testing DiscordBotService initialization..."
    begin
      service = DiscordBotService.new
      bot = service.instance_variable_get(:@bot)
      
      if bot
        puts "✅ Bot object created successfully"
        puts "   Bot class: #{bot.class.name}"
      else
        puts "❌ Bot object is nil - check DISCORD_BOT_TOKEN"
        exit 1
      end
    rescue => e
      puts "❌ Error initializing bot: #{e.message}"
      puts "   #{e.backtrace.first}"
      exit 1
    end
    
    puts
    
    # Test event handlers
    puts "Testing event handlers..."
    begin
      handlers = service.instance_variable_get(:@bot)&.instance_variable_get(:@event_handlers)
      if handlers && handlers.any?
        puts "✅ Event handlers registered: #{handlers.keys.join(', ')}"
      else
        puts "⚠️  No event handlers found (this might be normal)"
      end
    rescue => e
      puts "⚠️  Could not check event handlers: #{e.message}"
    end
    
    puts
    puts "=" * 80
    puts "✅ Basic initialization test passed!"
    puts
    puts "To test the full connection:"
    puts "  1. Start Rails server: rails server"
    puts "  2. Check Discord logs: tail -f ~/GuildSync/logs/discord.log"
    puts "  3. Look for 'Discord bot ready!' message"
    puts "=" * 80
  end
  
  desc "Check if Discord bot is running"
  task :status => :environment do
    log_file = File.join(Dir.home, 'GuildSync', 'logs', 'discord.log')
    
    if File.exist?(log_file)
      # Check last 50 lines for bot ready message
      last_lines = `tail -n 50 #{log_file}`.split("\n")
      ready_line = last_lines.find { |line| line.include?("Discord bot ready!") }
      
      if ready_line
        puts "✅ Discord bot appears to be running"
        puts "   Last ready message: #{ready_line}"
      else
        puts "⚠️  No 'ready' message found in recent logs"
        puts "   Bot may not be connected or server not started"
      end
      
      # Check for errors
      error_lines = last_lines.select { |line| line.match?(/ERROR|error|Error/) }
      if error_lines.any?
        puts
        puts "⚠️  Recent errors found:"
        error_lines.last(5).each { |line| puts "   #{line}" }
      end
    else
      puts "❌ Discord log file not found: #{log_file}"
      puts "   Start Rails server to create logs"
    end
  end
end

