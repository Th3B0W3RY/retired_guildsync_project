class GearController < ApplicationController
  include RequiresActiveGuildAccess

  # Skip CSRF for upload endpoint - authentication is handled by authenticate_user!
  # File uploads with FormData can have CSRF token issues, and we have proper auth
  skip_before_action :verify_authenticity_token, only: [:upload]
  prepend_before_action :force_json_format, only: [:upload]
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :ensure_guild_member, only: [:upload]
  before_action :ensure_can_view_gear, only: [:index, :show, :screenshot]
  before_action :ensure_can_request_gear, only: [:request_update, :request_bulk]
  
  def index
    # Handled by guilds#members_gear
    redirect_to guild_members_gear_path(@guild) if @guild
  end
  
  def upload
    begin
      unless params[:screenshot].present?
        return render json: { error: gear_error_with_support("gear.api.screenshot_required") }, status: :unprocessable_entity
      end
      
      # Validate file type
      allowed_types = ['image/png', 'image/jpeg', 'image/jpg', 'image/webp']
      unless allowed_types.include?(params[:screenshot].content_type)
        return render json: {
          error: gear_error_with_support("gear.api.invalid_file_type")
        }, status: :unprocessable_entity
      end
      
      # Validate file size (10MB max). Azure Image Analysis: 4MB (API 3.2) or 20MB (API 4.0). Client cap is configurable via GEAR_UPLOAD_MAX_MB when nginx allows (e.g. client_max_body_size 12M).
      max_size = 10.megabytes
      if params[:screenshot].size > max_size
        return render json: {
          error: gear_error_with_support("gear.api.file_too_large", max_mb: (max_size / 1.megabyte).to_i)
        }, status: :unprocessable_entity
      end
      
      # Determine game for this upload
      # Option 1: Game specified in params (for multi-game guilds)
      # Option 2: Use primary game if only one game
      # Option 3: Require game selection if multiple games
      game = if params[:game_id].present?
        @guild.games.find_by(id: params[:game_id])
      else
        @guild.primary_game || @guild.games.first
      end
      
      unless game
        if @guild.games.count > 1
          return render json: {
            error: t("gear.api.specify_game"),
            available_games: @guild.games.map { |g| { id: g.id, name: g.name } }
          }, status: :unprocessable_entity
        else
          return render json: {
            error: t("gear.api.guild_needs_game")
          }, status: :unprocessable_entity
        end
      end
      
      # Process OCR (pass game and current user for usage limits)
      Rails.logger.info "Starting OCR processing for game: #{game.name}"
      ocr_result = GearOcrService.process_image(
        params[:screenshot],
        game,
        user: current_user,
        request: request,
        guild: @guild
      )
      Rails.logger.info "OCR result: success=#{ocr_result[:success]}, error=#{ocr_result[:error]}, data_keys=#{ocr_result[:data]&.keys&.inspect}"
      
      unless ocr_result[:success]
        Rails.logger.error "OCR processing failed: #{ocr_result[:error]}"
        return render json: {
          error: gear_error_with_support("gear.api.ocr_failed"),
          details: ocr_result[:error]
        }, status: :unprocessable_entity
      end
      
      # Ensure data is not nil (validation requirement)
      ocr_result[:data] ||= {}
      
      # Rewind file pointer before next read (handle closed files)
      begin
        params[:screenshot].rewind if params[:screenshot].respond_to?(:rewind)
      rescue => e
        Rails.logger.warn "Could not rewind file: #{e.message}"
      end
      
      # Generate embedding (may return nil if generation fails - that's OK)
      embedding = begin
        GearEmbeddingService.generate_embedding(params[:screenshot])
      rescue => e
        Rails.logger.error "Embedding generation failed: #{e.message}"
        ErrorLogger.capture(
          e,
          context: {
            component: "GearController#upload",
            phase: "embedding",
            guild_id: @guild&.id,
            user_id: current_user&.id
          }.compact,
          severity: "medium"
        )
        nil
      end
      
      # Rewind file pointer before validation (uses game_id, not guild_id)
      begin
        params[:screenshot].rewind if params[:screenshot].respond_to?(:rewind)
      rescue => e
        Rails.logger.warn "Could not rewind file: #{e.message}"
      end
      
      validation_result = GearEmbeddingService.validate_embedding(embedding, game.id)

      # OCR can return text but parse to zero stats (e.g. wrong panel captured, or a stat panel
      # the region filter excluded). Keep the screenshot for retry/review (matches Discord), but
      # surface a warning so the UI does not report a misleading clean success.
      stats_extracted = ocr_result[:data].present?
      snapshot_warning = validation_result[:warning].presence
      snapshot_warning ||= t("gear.api.stats_not_extracted") unless stats_extracted

      # Always create new snapshot (keep history)
      snapshot = GearSnapshot.new(
        guild: @guild,
        user: current_user,
        game: game,
        source: 'web',
        raw_text: ocr_result[:raw_text],
        data: ocr_result[:data],
        embedding: embedding&.to_json,
        validation_passed: validation_result[:valid],
        validation_warning: snapshot_warning
      )
      
      # Rewind file pointer before attach
      begin
        params[:screenshot].rewind if params[:screenshot].respond_to?(:rewind)
      rescue => e
        Rails.logger.warn "Could not rewind file: #{e.message}"
      end
      
      # Attach screenshot before saving (required for validation)
      begin
        snapshot.screenshot.attach(params[:screenshot])
        # Force reload to ensure attachment is recognized
        snapshot.reload if snapshot.persisted?
        Rails.logger.info "Screenshot attached successfully, attached?=#{snapshot.screenshot.attached?}"
      rescue => e
        Rails.logger.error "Failed to attach screenshot: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        ErrorLogger.capture(
          e,
          context: {
            component: "GearController#upload",
            phase: "screenshot_attach",
            guild_id: @guild&.id,
            user_id: current_user&.id
          }.compact,
          severity: "medium"
        )
        return render json: {
          error: gear_error_with_support("gear.api.attach_screenshot_failed"),
          details: e.message
        }, status: :unprocessable_entity
      end
      
      # Verify screenshot is attached before saving
      unless snapshot.screenshot.attached?
        Rails.logger.error "Screenshot not attached after attach call - file may be invalid or too large"
        return render json: {
          error: gear_error_with_support("gear.api.attach_screenshot_invalid"),
          details: t("gear.api.attach_screenshot_invalid")
        }, status: :unprocessable_entity
      end
      
      Rails.logger.info "Attempting to save snapshot with data: #{snapshot.data.inspect}"
      if snapshot.save
        GearStatScanActivityLog.log_successful_upload(
          guild: @guild,
          initiated_by: current_user,
          game_name: game.name
        )
        Rails.logger.info "Snapshot saved successfully with ID: #{snapshot.id}"
        # Mark pending requests as completed
        GearUploadRequest.pending_for_user(@guild, current_user).each(&:mark_completed!)
        
        render json: {
          success: true,
          stats_extracted: stats_extracted,
          snapshot: {
            id: snapshot.id,
            data: snapshot.data,
            key_stats: snapshot.key_stats,
            validation_warning: snapshot.validation_warning,
            created_at: snapshot.created_at,
            last_activity_at: snapshot.last_activity_at
          }
        }
      else
        Rails.logger.error "Snapshot validation failed: #{snapshot.errors.full_messages.inspect}"
        Rails.logger.error "Snapshot attributes: guild_id=#{snapshot.guild_id}, user_id=#{snapshot.user_id}, game_id=#{snapshot.game_id}, source=#{snapshot.source}, data=#{snapshot.data.inspect}, screenshot_attached=#{snapshot.screenshot.attached?}"
        render json: {
          error: gear_error_with_support("gear.api.snapshot_save_failed"),
          errors: snapshot.errors.full_messages,
          details: snapshot.errors.details
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "Gear upload error: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      ErrorLogger.capture(
        e,
        context: {
          component: "GearController#upload",
          guild_id: @guild&.id,
          user_id: current_user&.id
        }.compact,
        severity: "high"
      )
      render json: {
        error: gear_error_with_support("gear.api.upload_error"),
        details: e.message,
        error_class: e.class.name
      }, status: :unprocessable_entity
    end
  end
  
  def show
    @target_user = @guild.members.find_by(id: params[:user_id])
    unless @target_user
      return render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
    end

    unless can_view_member_gear_stats?(@guild, @target_user)
      return render json: { error: t("guilds.member_stats.cannot_view_other_member_stats") }, status: :forbidden
    end

    @snapshot = GearSnapshot.latest_for_user(@guild, @target_user).first
    
    render json: {
      user: {
        id: @target_user.id,
        username: @target_user.display_name
      },
      snapshot: @snapshot ? {
        id: @snapshot.id,
        data: @snapshot.data,
        stat_rows: @snapshot.stat_rows.map { |r| { label: r.label, value: r.value } },
        raw_text: @snapshot.raw_text,
        created_at: @snapshot.created_at,
        last_activity_at: @snapshot.last_activity_at,
        status: @snapshot.status
      } : nil
    }
  end

  # Serves the latest stat screenshot inline (authorized like member stats). Expires with
  # GearSnapshot::RETENTION_PERIOD_DAYS — see PurgeExpiredGearSnapshotsJob.
  def screenshot
    @target_user = @guild.members.find_by(id: params[:user_id])
    unless @target_user
      respond_to do |format|
        format.html { redirect_to guild_members_gear_path(@guild), alert: t("controllers.guilds.access_denied") }
        format.any { head :not_found }
      end
      return
    end

    unless can_view_member_gear_stats?(@guild, @target_user)
      respond_to do |format|
        format.html do
          redirect_to guild_members_gear_path(@guild), alert: t("guilds.member_stats.cannot_view_other_member_stats")
        end
        format.any { head :forbidden }
      end
      return
    end

    snapshot = GearSnapshot.latest_for_user(@guild, @target_user).first
    unless snapshot&.reference_screenshot_available?
      respond_to do |format|
        format.html do
          redirect_to guild_members_gear_path(@guild), alert: t("guilds.members_gear.screenshot_unavailable")
        end
        format.any { head :not_found }
      end
      return
    end

    redirect_to rails_blob_path(snapshot.screenshot, disposition: "inline", only_path: true),
      allow_other_host: false
  end
  
  def request_update
    target_user = @guild.members.find_by(id: params[:user_id])
    unless target_user
      return render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
    end

    # Check if request already exists
    existing_request = GearUploadRequest.pending_for_user(@guild, target_user).first
    if existing_request
      return render json: {
        success: false,
        message: t("gear.api.request_already_pending", name: target_user.display_name),
        request_id: existing_request.id
      }, status: :unprocessable_entity
    end
    
    begin
      request = GearUploadRequest.create!(
        guild: @guild,
        requester: current_user,
        target_user: target_user,
        requested_at: Time.current
      )
      GuildActivityLogger.log(
        guild: @guild,
        user: current_user,
        action_type: "gear_requested",
        description: I18n.t("gear.activity.requested", name: target_user.display_name),
        target_name: target_user.display_name
      )
      
      # Trigger Discord notification (background job)
      DiscordGearRequestJob.perform_later(request.id) if defined?(DiscordGearRequestJob)
      
      render json: {
        success: true,
        message: t("gear.api.request_created", name: target_user.display_name),
        request_id: request.id
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: {
        error: t("gear.api.create_request_failed"),
        details: e.record.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  def request_bulk
    status_filter = params[:status] # 'missing', 'outdated', 'all', or nil for both
    
    begin
      target_users = case status_filter
      when 'missing'
        @guild.members.where.not(id: GearSnapshot.where(guild: @guild).select(:user_id))
      when 'outdated'
        outdated_snapshot_user_ids = GearSnapshot
          .where(guild: @guild)
          .outdated(7)
          .pluck(:user_id)
        @guild.members.where(id: outdated_snapshot_user_ids)
      else
        # Both missing and outdated
        missing_user_ids = @guild.members
          .where.not(id: GearSnapshot.where(guild: @guild).select(:user_id))
          .pluck(:id)
        outdated_user_ids = GearSnapshot
          .where(guild: @guild)
          .outdated(7)
          .pluck(:user_id)
        @guild.members.where(id: (missing_user_ids + outdated_user_ids).uniq)
      end
      
      # Handle empty target users
      if target_users.empty?
        return render json: {
          success: true,
          message: t("gear.api.no_members_match"),
          count: 0
        }
      end
      
      # Batch create requests (more efficient)
      requests = target_users.map do |user|
        next if GearUploadRequest.pending_for_user(@guild, user).exists?
        
        {
          guild_id: @guild.id,
          requester_id: current_user.id,
          target_user_id: user.id,
          status: 0,
          requested_at: Time.current,
          created_at: Time.current,
          updated_at: Time.current
        }
      end.compact
      
      # Handle case where all users already have pending requests
      if requests.empty?
        return render json: {
          success: true,
          message: t("gear.api.all_members_already_pending"),
          count: 0
        }
      end
      
      # Bulk insert with error handling
      begin
        GearUploadRequest.insert_all(requests)
      rescue => e
        Rails.logger.error "Bulk insert failed: #{e.message}"
        return render json: {
          error: t("gear.api.bulk_create_failed"),
          details: e.message
        }, status: :unprocessable_entity
      end
      
      # Trigger Discord notifications (background job with user IDs)
      if defined?(DiscordBulkGearRequestJob)
        DiscordBulkGearRequestJob.perform_later(@guild.id, current_user.id, requests.map { |r| r[:target_user_id] })
      end
      
      render json: {
        success: true,
        message: t("gear.api.created_requests", count: requests.size),
        count: requests.size
      }
    rescue => e
      Rails.logger.error "Bulk request failed: #{e.message}"
      render json: {
        error: t("gear.api.bulk_process_failed"),
        details: e.message
      }, status: :unprocessable_entity
    end
  end
  
  private

  def gear_error_with_support(i18n_key, **interp)
    "#{t(i18n_key, **interp)} #{t('gear.api.reach_guildsync_support')}"
  end
  
  def force_json_format
    request.format = :json
  end
  
  
  # Override Devise's authentication failure to return JSON instead of redirecting
  # Only for upload action which requires JSON responses
  def authenticate_user!
    if action_name == "upload" && !user_signed_in?
      render json: { error: t("api.v1.authentication_required") }, status: :unauthorized
      return false
    end
    super
  end
  
  def set_guild
    guild_id = params[:id] || params[:guild_id]
    unless guild_id.present?
      render json: { error: t("gear.api.guild_id_required") }, status: :bad_request
      return
    end

    @guild = current_user.guilds.find_by(id: guild_id)
    @guild ||= current_user.owned_guilds.find_by(id: guild_id)
    @guild ||= Guild.find_by(id: guild_id, owner_id: current_user.id)

    return if @guild

    render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
  end
  
  def ensure_guild_member
    return unless @guild # Don't check if guild wasn't found
    
    unless @guild.members.include?(current_user)
      render json: { error: t("gear.api.not_a_member") }, status: :forbidden
      return # Stop execution after rendering error
    end
  end
  
  def ensure_can_view_gear
    return unless @guild # Don't check if guild wasn't found
    
    # All guild members can view gear
    unless @guild.members.include?(current_user)
      render json: { error: t("gear.api.not_a_member") }, status: :forbidden
      return # Stop execution after rendering error
    end
  end
  
  def ensure_can_request_gear
    return unless @guild # Don't check if guild wasn't found
    
    # Only owners and officers can request gear updates
    # Use ApplicationController helper method
    unless can_manage_gear_requests?(@guild)
      render json: { error: t("api.v1.not_authorized") }, status: :forbidden
      return # Stop execution after rendering error
    end
  end
end

