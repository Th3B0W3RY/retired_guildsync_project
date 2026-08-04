namespace :discord do
  desc "Check Discord bot status"
  task status: :environment do
    service = discord_bot_service
    
    if service.nil?
      puts "❌ Discord bot service not initialized"
      exit 1
    end
    
    if service.connected?
      puts "✅ Discord bot is ONLINE and connected"
      puts "   Bot is ready to handle interactions"
    elsif service.running
      puts "⚠️  Discord bot is RUNNING but not connected"
      puts "   Auto-reconnect will attempt to restore connection"
    else
      puts "❌ Discord bot is NOT running"
      puts "   Starting bot..."
      service.start
      sleep(2)
      if service.connected?
        puts "✅ Bot started and connected!"
      else
        puts "⚠️  Bot starting (connection in progress...)"
      end
    end
  end

  desc "Restart Discord bot"
  task restart: :environment do
    service = discord_bot_service
    
    if service.nil?
      puts "❌ Discord bot service not initialized"
      exit 1
    end
    
    puts "Restarting Discord bot..."
    service.stop
    sleep(1)
    service.start
    sleep(2)
    
    if service.connected?
      puts "✅ Bot restarted and connected!"
    else
      puts "⚠️  Bot restarting (connection in progress...)"
    end
  end

  desc "Ensure Discord bot is running"
  task ensure_running: :environment do
    service = discord_bot_service
    
    if service.nil?
      puts "❌ Discord bot service not initialized"
      exit 1
    end
    
    service.ensure_running
    
    if service.connected?
      puts "✅ Discord bot is running and connected"
    else
      puts "⚠️  Discord bot is starting (will connect automatically)"
    end
  end
end

