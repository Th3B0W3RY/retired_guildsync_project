class GamesController < ApplicationController
  before_action :authenticate_user!, unless: :admin_authenticated?
  skip_before_action :ensure_fully_authenticated, if: :admin_authenticated?
  before_action :ensure_admin_access, except: [:search, :suggest]
  
  def index
    @games = Game.all.order(:name)
    @games = @games.where(active: params[:active] == 'true') if params[:active].present?
    # Only filter by guild_oriented if column exists (added in AddIgdbFieldsToGames migration)
    if params[:guild_oriented].present? && Game.column_names.include?('guild_oriented')
      @games = @games.where(guild_oriented: params[:guild_oriented] == 'true')
    end
    # Handle empty state - @games will be empty array, which is fine for views
    # Admins can filter by guild_oriented to review non-guild-oriented games
  end
  
  def show
    begin
      @game = Game.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to games_path, alert: t('controllers.games.not_found')
      return
    end
    
    @guild_count = @game.guilds.count
    @snapshot_count = @game.gear_snapshots.count
  end
  
  def new
    @game = Game.new
  end
  
  def create
    @game = Game.new(game_params)
    
    # Validate ocr_config if present
    if params[:game][:ocr_config].present?
      begin
        # Ensure it's valid JSON if it's a string
        if params[:game][:ocr_config].is_a?(String)
          JSON.parse(params[:game][:ocr_config])
        end
      rescue JSON::ParserError => e
          @game.errors.add(:ocr_config, "is not valid JSON: #{e.message}")
          flash.now[:alert] = @game.errors.full_messages.join(', ')
          render :new, status: :unprocessable_entity
          return
      end
    end
    
    if @game.save
      # No notifications for admin-created games
      redirect_to games_path, notice: t('controllers.games.created')
    else
      flash.now[:alert] = @game.errors.full_messages.join(', ')
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    begin
      @game = Game.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to games_path, alert: t('controllers.games.not_found')
    end
  end
  
  def update
    begin
      @game = Game.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to games_path, alert: t('controllers.games.not_found')
      return
    end
    
    # Validate ocr_config if present
    if params[:game][:ocr_config].present?
      begin
        # Ensure it's valid JSON if it's a string
        if params[:game][:ocr_config].is_a?(String)
          JSON.parse(params[:game][:ocr_config])
        end
      rescue JSON::ParserError => e
        @game.errors.add(:ocr_config, "is not valid JSON: #{e.message}")
        flash.now[:alert] = @game.errors.full_messages.join(', ')
        render :edit, status: :unprocessable_entity
        return
      end
    end
    
    if @game.update(game_params)
      redirect_to game_path(@game), notice: t('controllers.games.updated')
    else
      flash.now[:alert] = @game.errors.full_messages.join(', ')
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    begin
      @game = Game.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to games_path, alert: t('controllers.games.not_found')
      return
    end
    
    # Prevent deletion if game is in use
    if @game.guilds.any?
      redirect_to games_path, alert: t('controllers.games.has_guilds')
      return
    end
    
    # Also check for snapshots
    if @game.gear_snapshots.any?
      redirect_to games_path, alert: t('controllers.games.has_snapshots')
      return
    end
    
    if @game.destroy
      redirect_to games_path, notice: t('controllers.games.deleted')
    else
      redirect_to games_path, alert: t('controllers.games.delete_failed', errors: @game.errors.full_messages.join(', '))
    end
  end
  
  def toggle_active
    begin
      @game = Game.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to games_path, alert: t('controllers.games.not_found')
      return
    end
    
    was_active = @game.active?
    new_active_status = !was_active
    
    update_attrs = { active: new_active_status }
    
    if new_active_status
      # Reactivating: clear deactivation fields
      update_attrs[:deactivated_at] = nil
      update_attrs[:deactivated_by_id] = nil
      update_attrs[:deactivation_reason] = nil
    else
      # Deactivating: set deactivation fields
      update_attrs[:deactivated_at] = Time.current
      update_attrs[:deactivated_by_id] = current_user.id if current_user
      # Optional: could add deactivation_reason from params if needed
      # update_attrs[:deactivation_reason] = params[:deactivation_reason] if params[:deactivation_reason].present?
    end
    
    if @game.update(update_attrs)
      redirect_to games_path, notice: @game.active? ? t('controllers.games.activated') : t('controllers.games.deactivated')
    else
      redirect_to games_path, alert: t('controllers.games.toggle_failed', errors: @game.errors.full_messages.join(', '))
    end
  end
  
  # Public endpoint for searching games (fuzzy matching)
  def search
    query = sanitize_text_input(params[:q]).to_s
    
    if query.length < 2
      render json: { suggestions: [], can_create: false }
      return
    end
    
    # Find similar games
    suggestions = Game.find_similar(query, limit: 5, min_similarity: 0.3)
    
    # Check if exact match exists
    exact_match = Game.where("LOWER(name) = ?", query.downcase).first
    
    result = {
      suggestions: suggestions.map { |g| { id: g.id, name: g.name, active: g.active } },
      exact_match: exact_match ? { id: exact_match.id, name: exact_match.name } : nil,
      can_create: exact_match.nil? && suggestions.empty?
    }
    
    render json: result
  end
  
  # Public endpoint for suggesting/creating a new game
  # Creates game as inactive (pending admin approval)
  # NOTE: IGDB sync is handled by background job only to avoid rate limit issues
  # User-created games will be synced with IGDB on the next daily sync job
  def suggest
    game_name = sanitize_text_input(params[:name]).to_s
    
    if game_name.blank?
      render json: { error: t('controllers.games.suggest.name_required') }, status: :unprocessable_entity
      return
    end
    
    # Check for existing game (case-insensitive)
    existing = Game.where("LOWER(name) = ?", game_name.downcase).first
    if existing
      render json: { 
        error: t('controllers.games.suggest.already_exists'),
        game: { id: existing.id, name: existing.name, active: existing.active }
      }, status: :unprocessable_entity
      return
    end
    
    # Optional: Check IGDB if credentials are configured
    # This helps verify the game exists and get initial data
    # igdb_data = nil
    # if ENV['IGDB_CLIENT_ID'].present? && ENV['IGDB_CLIENT_SECRET'].present?
    #   begin
    #     igdb_results = IgdbService.search_games(game_name, limit: 1)
    #     if igdb_results.any?
    #       best_match = igdb_results.find { |g| g['name'].downcase == game_name.downcase } || igdb_results.first
    #       igdb_data = IgdbService.get_game_details(best_match['id']) if best_match
    #     end
    #   rescue => e
    #     Rails.logger.warn "IGDB check failed during game creation: #{e.message}"
    #     # Continue with creation even if IGDB check fails
    #   end
    # end
    
    # Generate slug from name
    slug = game_name.downcase
      .gsub(/[^a-z0-9\s-]/, '') # Remove special characters
      .gsub(/\s+/, '-')          # Replace spaces with hyphens
      .gsub(/-+/, '-')           # Replace multiple hyphens with single
      .gsub(/^-|-$/, '')         # Remove leading/trailing hyphens
    
    # Ensure slug is unique
    base_slug = slug
    counter = 1
    while Game.exists?(slug: slug)
      slug = "#{base_slug}-#{counter}"
      counter += 1
    end
    
    # Determine if game is guild-oriented from IGDB data (if available)
    # guild_oriented = false
    # if igdb_data
    #   analysis = IgdbService.is_guild_oriented?(igdb_data)
    #   guild_oriented = analysis[:guild_oriented]
    # end
    
    # Create game as inactive (pending approval)
    # IGDB sync will happen via background job (SyncGamesWithIgdbJob)
    # This prevents rate limit issues from user-generated API calls
    game_attributes = {
      name: game_name,
      slug: slug,
      description: sanitize_text_input(params[:description]).presence,
      active: false # Inactive until admin approves
    }
    
    # Only set IGDB-related attributes if the columns exist
    # These columns are added in a later migration (AddIgdbFieldsToGames)
    if Game.column_names.include?('guild_oriented')
      game_attributes[:guild_oriented] = false # Will be set by background job after IGDB sync
    end
    if Game.column_names.include?('verified_by_igdb')
      game_attributes[:verified_by_igdb] = false # Will be set by background job after IGDB sync
    end
    
    game = Game.new(game_attributes)
    
    if game.save
      # Notify admins about the new activation request
      # Only notify for pending games (never activated), not deactivated games
      # The current_user check ensures this is a legitimate user request that needs review.
      if game.pending? && current_user
        NotifyAdminsGameActivationRequestJob.perform_later(game.id, current_user.id)
      end
      
      render json: { 
        success: true,
        game: { 
          id: game.id, 
          name: game.name, 
          slug: game.slug,
          active: game.active,
          message: 'Game created successfully. It will be available after admin approval.'
        }
      }
    else
      render json: { 
        error: t('controllers.games.suggest.create_failed'),
        errors: game.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  private
  
  def admin_authenticated?
    session[:admin_authenticated] == true
  end
  
  def game_params
    permitted = params.require(:game).permit(
      :name,
      :slug,
      :description,
      :active,
      ocr_config: {}
    )
    sanitize_permitted_text_fields!(permitted, [:name, :slug, :description])
  end
  
  def ensure_admin_access
    unless admin_user?
      redirect_to root_path, alert: t('controllers.games.admin_required')
    end
  end
end

