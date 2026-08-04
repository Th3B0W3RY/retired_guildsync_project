require 'rest-client'
require 'json'

# Service for interacting with IGDB (Internet Game Database) API
# Documentation: https://api-docs.igdb.com/
#
# Environment Variables Required:
# - IGDB_CLIENT_ID: Your IGDB API client ID
# - IGDB_CLIENT_SECRET: Your IGDB API client secret
#
# Rate Limits (Free Tier):
# - 4 requests per second
# - 500 requests per 10 seconds
class IgdbService
  IGDB_API_BASE = 'https://api.igdb.com/v4'
  IGDB_TOKEN_URL = 'https://id.twitch.tv/oauth2/token'
  
  # Game modes that indicate guild-oriented gameplay
  GUILD_ORIENTED_MODES = [
    1,  # Single player (exclude)
    2,  # Multiplayer (include)
    3,  # Co-operative (include)
    4,  # Split screen (exclude)
    5,  # MMO (include - strongly guild-oriented)
    6,  # Battle Royale (include - team-based)
    7,  # Online Co-op (include)
    8,  # Local Co-op (exclude)
    9,  # Massively Multiplayer (include - strongly guild-oriented)
  ].freeze
  
  GUILD_ORIENTED_MODE_IDS = [2, 3, 5, 6, 7, 9].freeze
  
  # Game categories that indicate guild-oriented gameplay
  GUILD_ORIENTED_CATEGORIES = [
    0,  # Main game (neutral)
    1,  # DLC/Add-on (neutral)
    2,  # Expansion (neutral)
    3,  # Bundle (neutral)
    4,  # Standalone expansion (neutral)
    5,  # Mod (neutral)
    6,  # Episode (neutral)
    7,  # Season (neutral)
    8,  # Remake (neutral)
    9,  # Remaster (neutral)
    10, # Expanded game (neutral)
    11, # Port (neutral)
    12, # Fork (neutral)
    13, # Pack (neutral)
    14, # Update (neutral)
  ].freeze
  
  # Genres that are more likely to be guild-oriented
  GUILD_ORIENTED_GENRES = [
    12, # Role-playing (RPG) - often has guilds
    15, # Strategy - often multiplayer
    16, # MOBA - team-based
    31, # Adventure - can be multiplayer
  ].freeze
  
  class << self
    # Get access token from Twitch OAuth (required for IGDB API)
    def get_access_token
      client_id = ENV['IGDB_CLIENT_ID']
      client_secret = ENV['IGDB_CLIENT_SECRET']
      
      unless client_id.present? && client_secret.present?
        Rails.logger.warn 'IGDB credentials not configured. Set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET environment variables.'
        return nil
      end
      
      # Check cache first (tokens expire after ~60 days, but we'll refresh daily)
      cache_key = 'igdb_access_token'
      cached_token = Rails.cache.read(cache_key)
      return cached_token if cached_token.present?
      
      begin
        response = RestClient.post(
          IGDB_TOKEN_URL,
          {
            client_id: client_id,
            client_secret: client_secret,
            grant_type: 'client_credentials'
          }
        )
        
        token_data = JSON.parse(response.body)
        access_token = token_data['access_token']
        expires_in = token_data['expires_in'] || 60.days.to_i
        
        # Cache token (refresh 1 day before expiry)
        Rails.cache.write(cache_key, access_token, expires_in: expires_in - 1.day)
        
        Rails.logger.info "IGDB access token obtained successfully"
        access_token
      rescue RestClient::ExceptionWithResponse => e
        Rails.logger.error "Failed to get IGDB access token: #{e.response.body}"
        nil
      rescue => e
        Rails.logger.error "Error getting IGDB access token: #{e.message}"
        nil
      end
    end
    
    # Search for games by name
    # Returns array of game data with IGDB IDs
    def search_games(query, limit: 20)
      access_token = get_access_token
      return [] unless access_token
      
      # Rate limiting: max 4 requests per second
      sleep(0.25) if @last_request_time
      @last_request_time = Time.current
      
      begin
        # IGDB API v4 uses POST for queries
        # Fields: id, name, slug, game_modes, category, genres, summary, cover
        response = RestClient.post(
          "#{IGDB_API_BASE}/games",
          "search \"#{query}\"; fields id,name,slug,game_modes,category,genres,summary,cover.url; limit #{limit};",
          {
            'Client-ID' => ENV['IGDB_CLIENT_ID'],
            'Authorization' => "Bearer #{access_token}",
            'Content-Type' => 'text/plain'
          }
        )
        
        games = JSON.parse(response.body)
        Rails.logger.debug "IGDB search returned #{games.size} results for '#{query}'"
        games
      rescue RestClient::ExceptionWithResponse => e
        if e.response.code == 429
          Rails.logger.warn "IGDB rate limit hit. Waiting before retry..."
          sleep(1)
          return search_games(query, limit: limit) # Retry once
        end
        Rails.logger.error "IGDB search failed: #{e.response.code} - #{e.response.body}"
        []
      rescue => e
        Rails.logger.error "Error searching IGDB: #{e.message}"
        []
      end
    end
    
    # Get detailed game information by IGDB ID
    def get_game_details(igdb_id)
      access_token = get_access_token
      return nil unless access_token
      
      sleep(0.25) if @last_request_time
      @last_request_time = Time.current
      
      begin
        response = RestClient.post(
          "#{IGDB_API_BASE}/games",
          "fields id,name,slug,game_modes,category,genres,summary,cover.url,first_release_date,platforms.name; where id = #{igdb_id};",
          {
            'Client-ID' => ENV['IGDB_CLIENT_ID'],
            'Authorization' => "Bearer #{access_token}",
            'Content-Type' => 'text/plain'
          }
        )
        
        games = JSON.parse(response.body)
        games.first
      rescue RestClient::ExceptionWithResponse => e
        if e.response.code == 429
          Rails.logger.warn "IGDB rate limit hit. Waiting before retry..."
          sleep(1)
          return get_game_details(igdb_id) # Retry once
        end
        Rails.logger.error "IGDB get game details failed: #{e.response.code} - #{e.response.body}"
        nil
      rescue => e
        Rails.logger.error "Error getting IGDB game details: #{e.message}"
        nil
      end
    end
    
    # Determine if a game is guild-oriented based on IGDB data
    # Returns: { guild_oriented: boolean, confidence: float (0.0-1.0), reason: string }
    def is_guild_oriented?(igdb_game_data)
      return { guild_oriented: false, confidence: 0.0, reason: 'No IGDB data provided' } unless igdb_game_data
      
      game_modes = igdb_game_data['game_modes'] || []
      category = igdb_game_data['category'] || 0
      genres = igdb_game_data['genres'] || []
      
      score = 0.0
      reasons = []
      
      # Check game modes (strongest indicator)
      if game_modes.any?
        guild_modes = game_modes & GUILD_ORIENTED_MODE_IDS
        if guild_modes.include?(5) || guild_modes.include?(9) # MMO or Massively Multiplayer
          score += 1.0
          reasons << 'MMO/Massively Multiplayer'
        elsif guild_modes.any?
          score += 0.7
          reasons << "Multiplayer modes: #{guild_modes.join(', ')}"
        end
        
        # Penalize if ONLY single-player mode
        if game_modes == [1] && guild_modes.empty?
          score = 0.0
          reasons << 'Single-player only'
        end
      end
      
      # Check genres (moderate indicator)
      if genres.any?
        guild_genres = genres & GUILD_ORIENTED_GENRES
        if guild_genres.any?
          score += 0.3
          reasons << "Guild-oriented genres: #{guild_genres.join(', ')}"
        end
      end
      
      # Check category (weak indicator, mainly to exclude DLC/expansions)
      if category == 0 # Main game
        score += 0.1
      end
      
      # Normalize score to 0.0-1.0
      confidence = [score, 1.0].min
      guild_oriented = confidence >= 0.5 # Threshold: 50% confidence
      
      {
        guild_oriented: guild_oriented,
        confidence: confidence,
        reason: reasons.any? ? reasons.join('; ') : 'No strong indicators'
      }
    end
    
    # Fetch popular games from IGDB, filtered by guild-oriented criteria
    # Returns array of game data sorted by rating (most popular first)
    def fetch_popular_games(limit: 50, min_rating: 50)
      access_token = get_access_token
      return [] unless access_token
      
      # Rate limiting: max 4 requests per second
      sleep(0.25) if @last_request_time
      @last_request_time = Time.current
      
      begin
        # Query for popular games with guild-oriented modes
        # Sort by total_rating_count (number of ratings) descending - indicates popularity
        # Fields needed for guild-oriented analysis
        # Note: IGDB uses array syntax for game_modes - we'll filter in Ruby after fetching
        # Using total_rating_count for sorting as it better indicates popularity/engagement
        # Fetch more games than needed since we'll filter to guild-oriented ones
        query = <<~QUERY
          fields id,name,slug,game_modes,category,genres,summary,cover.url,total_rating,total_rating_count;
          sort total_rating_count desc;
          limit #{limit * 3};
        QUERY
        
        response = RestClient.post(
          "#{IGDB_API_BASE}/games",
          query,
          {
            'Client-ID' => ENV['IGDB_CLIENT_ID'],
            'Authorization' => "Bearer #{access_token}",
            'Content-Type' => 'text/plain'
          }
        )
        
        games = JSON.parse(response.body)
        Rails.logger.debug "IGDB popular games query returned #{games.size} results"
        
        # Filter to only guild-oriented games
        # First, filter by game_modes (quick check)
        games_with_guild_modes = games.select do |game_data|
          game_modes = game_data['game_modes'] || []
          (game_modes & GUILD_ORIENTED_MODE_IDS).any?
        end
        
        # Then use our full algorithm to ensure they're truly guild-oriented
        guild_oriented_games = games_with_guild_modes.select do |game_data|
          analysis = is_guild_oriented?(game_data)
          analysis[:guild_oriented]
        end
        
        # Limit to requested number
        guild_oriented_games = guild_oriented_games.first(limit)
        
        Rails.logger.debug "Filtered to #{guild_oriented_games.size} guild-oriented games"
        guild_oriented_games
      rescue RestClient::ExceptionWithResponse => e
        if e.response.code == 429
          Rails.logger.warn "IGDB rate limit hit. Waiting before retry..."
          sleep(1)
          return fetch_popular_games(limit: limit, min_rating: min_rating) # Retry once
        end
        Rails.logger.error "IGDB popular games fetch failed: #{e.response.code} - #{e.response.body}"
        []
      rescue => e
        Rails.logger.error "Error fetching popular games from IGDB: #{e.message}"
        []
      end
    end
    
    # Sync a single game with IGDB data
    # Returns: { success: boolean, game: Game, igdb_data: hash, guild_oriented: boolean }
    def sync_game(game)
      return { success: false, error: 'Game not found' } unless game
      
      # If game already has IGDB ID, fetch details
      if game.igdb_id.present?
        igdb_data = get_game_details(game.igdb_id)
        if igdb_data
          return update_game_from_igdb(game, igdb_data)
        end
      end
      
      # Otherwise, search for the game
      search_results = search_games(game.name, limit: 5)
      return { success: false, error: 'No IGDB results found' } if search_results.empty?
      
      # Find best match (exact name match preferred)
      best_match = search_results.find { |g| g['name'].downcase == game.name.downcase } || search_results.first
      
      # Get full details for the best match
      igdb_data = get_game_details(best_match['id'])
      return { success: false, error: 'Failed to get game details' } unless igdb_data
      
      update_game_from_igdb(game, igdb_data)
    end
    
    private
    
    def update_game_from_igdb(game, igdb_data)
      analysis = is_guild_oriented?(igdb_data)
      
      # Build update attributes, only including columns that exist
      update_attrs = {
        igdb_id: igdb_data['id'],
        igdb_data: igdb_data
      }
      
      # Only set these if columns exist (added in AddIgdbFieldsToGames migration)
      if Game.column_names.include?('igdb_synced_at')
        update_attrs[:igdb_synced_at] = Time.current
      end
      if Game.column_names.include?('guild_oriented')
        update_attrs[:guild_oriented] = analysis[:guild_oriented]
      end
      if Game.column_names.include?('verified_by_igdb')
        update_attrs[:verified_by_igdb] = true
      end
      
      game.update!(update_attrs)
      
      {
        success: true,
        game: game,
        igdb_data: igdb_data,
        guild_oriented: analysis[:guild_oriented],
        confidence: analysis[:confidence],
        reason: analysis[:reason]
      }
    rescue => e
      Rails.logger.error "Error updating game from IGDB: #{e.message}"
      { success: false, error: e.message }
    end
  end
end

