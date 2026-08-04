namespace :discord do
  desc "View recent Discord webhook logs"
  task :logs, [:lines] => :environment do |t, args|
    lines = (args[:lines] || 100).to_i
    # Use the custom log directory
    log_dir = if Gem.win_platform?
      File.join(ENV['LOCALAPPDATA'], 'GuildSync', 'logs')
    else
      File.join(Dir.home, 'GuildSync', 'logs')
    end
    log_file = File.join(log_dir, "discord.log")
    
    puts "=" * 80
    puts "DISCORD WEBHOOK LOGS (last #{lines} lines)"
    puts "=" * 80
    puts "Log file: #{log_file}"
    puts "=" * 80
    puts
    
    if File.exist?(log_file)
      # Get last N lines from Discord log file
      `tail -n #{lines} #{log_file}`.split("\n").each do |line|
        puts line
      end
    else
      puts "Discord log file not found: #{log_file}"
      puts "Make sure the logging system has been initialized."
    end
    
    puts
    puts "=" * 80
    puts "To view all Discord logs, run: tail -f #{log_file}"
    puts "=" * 80
  end
  
  desc "Monitor Discord webhook logs in real-time"
  task :monitor => :environment do
    # Use the custom log directory
    log_dir = if Gem.win_platform?
      File.join(ENV['LOCALAPPDATA'], 'GuildSync', 'logs')
    else
      File.join(Dir.home, 'GuildSync', 'logs')
    end
    log_file = File.join(log_dir, "discord.log")
    
    puts "Monitoring Discord webhook logs. Press Ctrl+C to stop."
    puts "Log file: #{log_file}"
    puts "=" * 80
    
    if File.exist?(log_file)
      exec "tail -f #{log_file}"
    else
      puts "Discord log file not found: #{log_file}"
      puts "Make sure the logging system has been initialized."
      exit 1
    end
  end
end

