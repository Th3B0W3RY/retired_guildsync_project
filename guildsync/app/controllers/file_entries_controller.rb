# frozen_string_literal: true

class FileEntriesController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :ensure_mfa_session_flags
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :ensure_guild_member
  before_action :check_permissions, except: [:show, :download]
  before_action :set_file_entry, only: [:show, :update, :destroy, :download]

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
    uploaded_files = params[:files] || []
    
    if uploaded_files.empty?
      render json: { error: t('controllers.file_entries.no_files_selected') }, status: :unprocessable_entity
      return
    end

    folder_id = params[:folder_id].presence
    folder = folder_id ? @guild.folders.find_by(id: folder_id) : nil

    created_files = []
    errors = []

    uploaded_files.each do |file|
      next unless file.is_a?(ActionDispatch::Http::UploadedFile)

      file_entry = @guild.file_entries.build(
        name: file.original_filename,
        folder: folder,
        uploaded_by: current_user.id
      )

      file_entry.file.attach(file)
      
      # Set metadata after attach
      if file_entry.file.attached?
        blob = file_entry.file.blob
        file_entry.content_type = blob.content_type
        file_entry.size = blob.byte_size
      end

      if file_entry.save
        created_files << file_entry
      else
        errors << { filename: file.original_filename, errors: file_entry.errors.full_messages }
      end
    end

    if errors.any?
      render json: { 
        success: created_files.any?,
        created: created_files.map { |f| { id: f.id, name: f.name } },
        errors: errors
      }, status: :unprocessable_entity
    else
      render json: { 
        success: true,
        created: created_files.map { |f| { id: f.id, name: f.name } }
      }
    end
  end

  def update
    if @file_entry.update(file_entry_params)
      render json: { success: true, file_entry: @file_entry }
    else
      render json: { error: @file_entry.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def destroy
    @file_entry.soft_delete!
    render json: { success: true }
  end

  def bulk_destroy
    file_ids = Array(params[:file_ids]).reject(&:blank?)
    
    if file_ids.empty?
      render json: { error: t('controllers.file_entries.no_files_selected') }, status: :unprocessable_entity
      return
    end

    file_entries = @guild.file_entries.where(id: file_ids)
    count = file_entries.count
    file_entries.find_each(&:soft_delete!)

    render json: { success: true, deleted_count: count }
  end

  def bulk_move
    file_ids = Array(params[:file_ids]).reject(&:blank?)
    folder_id = params[:folder_id].presence
    
    if file_ids.empty?
      render json: { error: t('controllers.file_entries.no_files_selected') }, status: :unprocessable_entity
      return
    end

    folder = folder_id ? @guild.folders.find_by(id: folder_id) : nil
    
    file_entries = @guild.file_entries.where(id: file_ids)
    file_entries.update_all(folder_id: folder&.id)
    
    render json: { success: true, moved_count: file_entries.count }
  end

  def download
    # Additional security: ensure user is a member before allowing download
    unless guild_member_or_owner?
      redirect_to root_path, alert: t('controllers.file_entries.not_member')
      return
    end

    if @file_entry.file.attached?
      redirect_to rails_blob_path(@file_entry.file, disposition: "attachment")
    else
      redirect_to guild_storage_path(@guild), alert: t('controllers.file_entries.not_found')
    end
  end

  def show
    # Additional security: ensure user is a member before allowing view
    unless guild_member_or_owner?
      redirect_to root_path, alert: t('controllers.file_entries.not_member')
      return
    end
    # View file details
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

  def set_file_entry
    @file_entry = @guild.file_entries.find(params[:id])
  end

  def file_entry_params
    permitted = params.require(:file_entry).permit(:name, :folder_id)
    sanitize_permitted_text_fields!(permitted, [:name])
  end

  def ensure_guild_member
    unless guild_member_or_owner?
      redirect_to root_path, alert: t('controllers.file_entries.not_member')
    end
  end

  def check_permissions
    unless can_manage_files?(@guild)
      redirect_to guild_storage_path(@guild), alert: t('controllers.file_entries.manage_denied')
    end
  end

  def guild_member_or_owner?
    @guild.owner_id == current_user.id || @guild.guild_members.active.exists?(user_id: current_user.id)
  end
end
