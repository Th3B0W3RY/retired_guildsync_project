# frozen_string_literal: true

class FoldersController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :ensure_mfa_session_flags
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :check_permissions
  before_action :set_folder, only: [:show, :update, :destroy]
  before_action :force_json_format, only: [:create]

  def ensure_mfa_session_flags
    return unless user_signed_in? && current_user.present?

    if current_user.oauth_primary_auth?
      unless session[:mfa_verified]
        session[:mfa_verified] = true
        session[:mfa_verified_at] = Time.current.to_i
      end
    elsif current_user.mfa_enabled? && current_user.mfa_verified?
      if session[:mfa_verified] && session[:mfa_verified_at]
        verified_at = Time.at(session[:mfa_verified_at])
        if verified_at > 30.minutes.ago
          session[:mfa_verified_at] = Time.current.to_i
        end
      end
    end

    session.save if session.respond_to?(:save)
  end

  def create
    begin
      @folder = @guild.folders.build(folder_params)
      @folder.parent_folder = @guild.folders.find_by(id: params[:parent_folder_id]) if params[:parent_folder_id].present?

      if @folder.save
        respond_to do |format|
          format.json { render json: { success: true, folder: { id: @folder.id, name: @folder.name } } }
          format.html { redirect_to guild_storage_path(@guild), notice: t('controllers.folders.created') }
        end
      else
        respond_to do |format|
          format.json { render json: { success: false, error: @folder.errors.full_messages.join(", ") }, status: :unprocessable_entity }
          format.html { redirect_to guild_storage_path(@guild), alert: t('controllers.folders.create_error', errors: @folder.errors.full_messages.join(', ')) }
        end
      end
    rescue ActionController::ParameterMissing => e
      respond_to do |format|
        format.json do
          render json: {
            success: false,
            error: t("controllers.folders.missing_required_parameter", param: e.param)
          }, status: :bad_request
        end
        format.html do
          redirect_to guild_storage_path(@guild),
            alert: t("controllers.folders.missing_required_parameter", param: e.param)
        end
      end
    rescue => e
      respond_to do |format|
        format.json do
          render json: {
            success: false,
            error: t("controllers.folders.unexpected_create_error", message: e.message)
          }, status: :unprocessable_entity
        end
        format.html do
          redirect_to guild_storage_path(@guild),
            alert: t("controllers.folders.unexpected_create_error", message: e.message)
        end
      end
    end
  end

  def update
    # Prevent moving folder into itself or its descendants
    if params[:folder][:parent_folder_id].present?
      new_parent = @guild.folders.find_by(id: params[:folder][:parent_folder_id])
      if new_parent && (new_parent == @folder || @folder.subfolders.include?(new_parent) || folder_is_descendant?(new_parent, @folder))
        render json: { error: t('controllers.folders.cannot_move_into_self') }, status: :unprocessable_entity
        return
      end
    end

    if @folder.update(folder_params)
      render json: { success: true, folder: @folder }
    else
      render json: { error: @folder.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def destroy
    if @folder.has_contents?
      render json: { error: t('controllers.folders.not_empty') }, status: :unprocessable_entity
      return
    end

    @folder.soft_delete!
    render json: { success: true }
  end

  def show
    @folders = @folder.subfolders.ordered
    @file_entries = @folder.file_entries.includes(:uploader).ordered
    render json: { 
      folder: @folder,
      folders: @folders,
      file_entries: @file_entries.map { |fe| 
        {
          id: fe.id,
          name: fe.name,
          size: fe.size,
          content_type: fe.content_type,
          uploaded_by: fe.uploader&.email,
          created_at: fe.created_at
        }
      }
    }
  end

  private

  def set_guild
    gid = params[:guild_id]
    @guild = current_user.guilds.find_by(id: gid)
    @guild ||= current_user.owned_guilds.find_by(id: gid)
    @guild ||= Guild.find_by(id: gid, owner_id: current_user.id)
    return if @guild

    session.save if session.respond_to?(:save)
    if request.format.json? || request.headers["Accept"].to_s.include?("application/json")
      render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
    else
      redirect_to my_guilds_path, alert: t("controllers.guilds.access_denied")
    end
  end

  def set_folder
    @folder = @guild.folders.find(params[:id])
  end

  def folder_params
    # Handle both nested and flat parameter structures
    permitted = if params[:folder].present?
      params.require(:folder).permit(:name, :parent_folder_id)
    else
      # Fallback if folder params are missing - create a hash
      ActionController::Parameters.new(name: params[:name]).permit(:name)
    end
    sanitize_permitted_text_fields!(permitted, [:name])
  end
  
  def force_json_format
    request.format = :json
  end

  def check_permissions
    unless can_manage_files?(@guild)
      redirect_to guild_storage_path(@guild), alert: t('controllers.folders.manage_denied')
    end
  end

  def folder_is_descendant?(ancestor, folder)
    return false unless folder.parent_folder
    return true if folder.parent_folder == ancestor
    folder_is_descendant?(ancestor, folder.parent_folder)
  end
end
