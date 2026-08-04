# frozen_string_literal: true

class StorageController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :ensure_mfa_session_flags
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :require_file_storage_plan!
  before_action :ensure_guild_member

  def show
    @current_folder = params[:folder_id].present? ? @guild.folders.find_by(id: params[:folder_id]) : nil

    # Get folders for the current location
    if @current_folder
      @folders = @current_folder.subfolders.ordered
      @file_entries = @current_folder.file_entries.includes(:uploader).ordered
    else
      @folders = @guild.folders.root_folders.ordered
      @file_entries = @guild.file_entries.root_files.includes(:uploader).ordered
    end

    # Build folder tree for sidebar
    @folder_tree = build_folder_tree(@guild.folders.root_folders.ordered)
  end

  private

  def require_file_storage_plan!
    return if current_user.plan_allows?(:file_storage)

    redirect_to upgrade_pricing_path, alert: t("plan_entitlements.upgrade_required")
  end

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

  def set_guild
    gid = params[:guild_id]
    @guild = current_user.guilds.find_by(id: gid)
    @guild ||= current_user.owned_guilds.find_by(id: gid)
    @guild ||= Guild.find_by(id: gid, owner_id: current_user.id)
    return if @guild

    session.save if session.respond_to?(:save)
    redirect_to my_guilds_path, alert: t("controllers.guilds.access_denied")
  end

  def ensure_guild_member
    unless @guild.members.include?(current_user) || @guild.owner == current_user
      redirect_to root_path, alert: t('controllers.storage.not_member')
    end
  end

  def build_folder_tree(folders, level = 0)
    folders.map do |folder|
      {
        folder: folder,
        level: level,
        subfolders: build_folder_tree(folder.subfolders.ordered, level + 1)
      }
    end
  end
end
