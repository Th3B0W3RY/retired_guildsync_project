# lib/game_initializer.rb

# Initializer to ensure popular guild-oriented games exist in the database
# Fetches top 40 popular games from IGDB that are potentially guild-oriented
# Only runs if IGDB credentials are configured
class GameInitializer
  # Number of games to initialize
  INITIAL_GAME_COUNT = 40
  
  def self.ensure_games_exist!
    return true unless defined?(Game)
    return true unless Game.table_exists?
    
    # Check if IGDB columns exist (added in AddIgdbFieldsToGames migration)
    unless Game.column_names.include?('igdb_id')
      Rails.logger.debug "IGDB columns not present yet, skipping game initialization"
      return true
    end
    
    # Check if IGDB credentials are configured
    unless ENV['IGDB_CLIENT_ID'].present? && ENV['IGDB_CLIENT_SECRET'].present?
      Rails.logger.debug "IGDB credentials not configured, skipping game initialization"
      return true
    end
    
    # Count existing active games with IGDB data
    existing_count = Game.active.where.not(igdb_id: nil).count
    
    # Only initialize if we have fewer than INITIAL_GAME_COUNT games
    if existing_count >= INITIAL_GAME_COUNT
      puts "  ✓ Games: OK (#{existing_count} games with IGDB data)"
      return true
    end
    
    games_needed = INITIAL_GAME_COUNT - existing_count
    Rails.logger.info "Initializing #{games_needed} popular games from IGDB"
    
    # Fetch popular games from IGDB
    # Fetch more than needed to account for games that might already exist
    popular_games = IgdbService.fetch_popular_games(limit: games_needed * 2, min_rating: 50)
    
    if popular_games.empty?
      puts "  ✗ Games: FAILED - No games returned from IGDB"
      return false
    end
    
    created_count = 0
    skipped_count = 0
    error_count = 0
    
    popular_games.each do |igdb_game_data|
      break if created_count >= games_needed
      
      igdb_id = igdb_game_data['id']
      game_name = igdb_game_data['name']
      
      # Skip if game already exists
      if Game.exists?(igdb_id: igdb_id)
        skipped_count += 1
        next
      end
      
      # Generate slug from name
      slug = game_name.parameterize
      
      # Ensure slug is unique
      base_slug = slug
      counter = 1
      while Game.exists?(slug: slug)
        slug = "#{base_slug}-#{counter}"
        counter += 1
      end
      
      begin
        # Create game with IGDB data
        game = Game.create!(
          name: game_name,
          slug: slug,
          description: igdb_game_data['summary'] || '',
          active: true,
          ocr_config: {},
          igdb_id: igdb_id,
          igdb_data: igdb_game_data,
          igdb_synced_at: Time.current,
          guild_oriented: true, # Already filtered by fetch_popular_games
          verified_by_igdb: true
        )
        
        created_count += 1
        Rails.logger.debug "Created game: #{game_name} (IGDB ID: #{igdb_id})"
      rescue => e
        error_count += 1
        Rails.logger.error "Failed to create game #{game_name}: #{e.message}"
      end
      
      # Rate limiting: small delay between creates
      sleep(0.1) if created_count < games_needed
    end
    
    if created_count > 0 || skipped_count > 0
      puts "  ✓ Games: OK (#{created_count} created, #{skipped_count} skipped, #{error_count} errors)"
      true
    else
      puts "  ✗ Games: FAILED - #{error_count} errors, no games created"
      false
    end
  rescue => e
    puts "  ✗ Games: FAILED - #{e.message}"
    Rails.logger.error "Game initialization error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    false
  end
end

