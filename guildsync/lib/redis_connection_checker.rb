class RedisConnectionChecker
  def self.check!
    Redis.new.ping
    puts "  ✓ Redis: OK"
    true
  rescue => e
    if defined?(GuildsyncLoggers)
      GuildsyncLoggers.error(GuildsyncLoggers.redis_logs, "Redis connection failed: #{e.class} - #{e.message}")
    end
    puts "  ✗ Redis: FAILED - #{e.message}"
    false
  end
end
