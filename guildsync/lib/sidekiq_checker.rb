class SidekiqChecker
  def self.check!
    require "sidekiq/api"
    Sidekiq::Stats.new.processed # Touch API to confirm availability
    puts "  ✓ Sidekiq: OK"
    true
  rescue => e
    puts "  ✗ Sidekiq: FAILED - #{e.message}"
    false
  end
end
