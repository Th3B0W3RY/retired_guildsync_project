# Background job to sync games with IGDB API
# Runs daily to update game data and identify non-guild-oriented games
#
# This job:
# 1. Fetches all active games that haven't been synced in 24+ hours
# 2. Queries IGDB API for each game
# 3. Updates game data with IGDB information
# 4. Marks games as guild-oriented or not based on game modes/genres
# 5. Non-guild-oriented games remain in database but are filtered from regular user views
#    (Admins can review all games in the admin console)
#
# Rate Limiting:
# - IGDB free tier: 4 requests/second, 500 requests/10 seconds
# - This job processes games in batches with delays to respect rate limits
class SyncGamesWithIgdbJob < ApplicationJob
  queue_as :low
  
  # Process games in batches to respect rate limits
  BATCH_SIZE = 10
  DELAY_BETWEEN_BATCHES = 3.seconds # Conservative delay for 4 req/sec limit
  DELAY_BETWEEN_REQUESTS = 0.3.seconds # 3 requests per second to be safe
  
  def perform
    Rails.logger.info "Starting IGDB game sync job"
    
    # Get games that need syncing:
    # - Active games that haven't been synced in 24+ hours
    # - Or games that have never been synced
    # Only query if igdb_synced_at column exists (added in AddIgdbFieldsToGames migration)
    games_to_sync = if Game.column_names.include?('igdb_synced_at')
      Game.active
        .where('igdb_synced_at IS NULL OR igdb_synced_at < ?', 24.hours.ago)
        .order(:created_at)
        .limit(100) # Process max 100 games per run to avoid timeout
    else
      # If column doesn't exist, no games need syncing yet
      Game.none
    end
    
    if games_to_sync.empty?
      Rails.logger.info "No games need IGDB syncing"
      return
    end
    
    Rails.logger.info "Syncing #{games_to_sync.count} games with IGDB"
    
    synced_count = 0
    failed_count = 0
    non_guild_oriented_count = 0
    
    games_to_sync.find_each.with_index do |game, index|
      # Rate limiting: delay between requests
      sleep(DELAY_BETWEEN_REQUESTS) if index > 0
      
      # Process in batches with longer delay
      if index > 0 && (index % BATCH_SIZE == 0)
        Rails.logger.info "Processed #{index} games, pausing for rate limit..."
        sleep(DELAY_BETWEEN_BATCHES)
      end
      
      begin
        result = IgdbService.sync_game(game)
        
        if result[:success]
          synced_count += 1
          
          # Log non-guild-oriented games for admin review
          # Games remain in database but are filtered from regular user views via guild_oriented scope
          if !result[:guild_oriented]
            non_guild_oriented_count += 1
            Rails.logger.info "Game marked as non-guild-oriented: #{game.name} (reason: #{result[:reason]}, confidence: #{result[:confidence]}) - Available for admin review"
          else
            Rails.logger.debug "Synced game: #{game.name} (guild-oriented: #{result[:guild_oriented]}, confidence: #{result[:confidence]})"
          end
        else
          failed_count += 1
          Rails.logger.warn "Failed to sync game #{game.name}: #{result[:error]}"
        end
      rescue => e
        failed_count += 1
        Rails.logger.error "Error syncing game #{game.name}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end
    
    Rails.logger.info "IGDB sync completed: #{synced_count} synced, #{failed_count} failed, #{non_guild_oriented_count} non-guild-oriented (available for admin review)"
    
    {
      synced: synced_count,
      failed: failed_count,
      non_guild_oriented: non_guild_oriented_count,
      total: games_to_sync.count
    }
  end
end

