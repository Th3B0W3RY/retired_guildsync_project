# frozen_string_literal: true

class DiscordRolesController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :require_can_manage_roles_for_discord_sync
  before_action :check_discord_connected

  # GET /guilds/:id/discord_roles
  def index
    begin
      discord_service = DiscordService.new(bot_token: bot_token)
      roles = discord_service.get_guild_roles(@discord_guild_id)
      
      # Get synced role IDs for this guild
      synced_role_ids = @guild.discord_role_syncs.pluck(:role_id).to_set
      
      # Format roles with sync status
      formatted_roles = roles.map do |role|
        {
          id: role["id"],
          name: role["name"],
          synced: synced_role_ids.include?(role["id"])
        }
      end
      
      render json: { roles: formatted_roles }
    rescue => e
      Rails.logger.error "Failed to fetch Discord roles: #{e.message}"
      render json: { error: t("discord_roles.api.fetch_failed", message: e.message) }, status: :internal_server_error
    end
  end

  # POST /guilds/:id/discord_roles/sync
  def sync
    role_id = params[:role_id]
    role_name = params[:role_name]

    unless role_id.present? && role_name.present?
      render json: { error: t("discord_roles.api.role_id_and_name_required") }, status: :unprocessable_entity
      return
    end

    # Check if already synced
    existing_sync = @guild.discord_role_syncs.find_by(role_id: role_id)
    if existing_sync
      render json: { message: t("discord_roles.api.already_synced"), role: existing_sync }, status: :ok
      return
    end

    # Create sync
    sync = @guild.discord_role_syncs.create!(
      role_id: role_id,
      role_name: role_name
    )
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "discord_role_synced", description: "Synced Discord role \"#{role_name}\"", name: role_name)

    render json: { message: t("discord_roles.api.synced_successfully"), role: sync }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  rescue => e
    Rails.logger.error "Failed to sync Discord role: #{e.message}"
    render json: { error: t("discord_roles.api.sync_failed", message: e.message) }, status: :internal_server_error
  end

  # DELETE /guilds/:id/discord_roles/sync/:role_id
  def destroy
    role_id = params[:role_id] || params[:id]

    unless role_id.present?
      render json: { error: t("discord_roles.api.role_id_required") }, status: :unprocessable_entity
      return
    end

    sync = @guild.discord_role_syncs.find_by(role_id: role_id)
    
    if sync
      role_name = sync.role_name
      sync.destroy
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "discord_role_unsynced", description: "Removed Discord role sync \"#{role_name}\"", name: role_name)
      render json: { message: t("discord_roles.api.removed_successfully") }, status: :ok
    else
      render json: { error: t("discord_roles.api.sync_not_found") }, status: :not_found
    end
  rescue => e
    Rails.logger.error "Failed to remove Discord role sync: #{e.message}"
    render json: { error: t("discord_roles.api.remove_sync_failed", message: e.message) }, status: :internal_server_error
  end

  # POST /guilds/:id/discord_roles/sync_all
  def sync_all
    begin
      discord_service = DiscordService.new(bot_token: bot_token)
      roles = discord_service.get_guild_roles(@discord_guild_id)
      
      synced_count = 0
      errors = []
      
      roles.each do |role|
        next if @guild.discord_role_syncs.exists?(role_id: role["id"])
        
        begin
          @guild.discord_role_syncs.create!(
            role_id: role["id"],
            role_name: role["name"]
          )
          synced_count += 1
        rescue => e
          errors << t("discord_roles.api.per_role_sync_failed", name: role["name"], message: e.message)
        end
      end
      
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "discord_roles_synced_all", description: "Synced #{synced_count} Discord roles to guild") if synced_count > 0
      render json: {
        message: t("discord_roles.api.synced_roles_count", count: synced_count),
        synced_count: synced_count,
        errors: errors
      }, status: :ok
    rescue => e
      Rails.logger.error "Failed to sync all Discord roles: #{e.message}"
      render json: { error: t("discord_roles.api.sync_all_failed", message: e.message) }, status: :internal_server_error
    end
  end

  # DELETE /guilds/:id/discord_roles/sync_all
  def destroy_all
    count = @guild.discord_role_syncs.count
    @guild.discord_role_syncs.destroy_all
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "discord_roles_unsynced_all", description: "Removed #{count} Discord role sync(s)")
    
    render json: { message: t("discord_roles.api.removed_syncs_count", count: count) }, status: :ok
  rescue => e
    Rails.logger.error "Failed to remove all Discord role syncs: #{e.message}"
    render json: { error: t("discord_roles.api.destroy_all_failed", message: e.message) }, status: :internal_server_error
  end

  private

  def set_guild
    guild_id = params[:guild_id] || params[:id]
    @guild = current_user.guilds.find_by(id: guild_id)
    @guild ||= current_user.owned_guilds.find_by(id: guild_id)
    @guild ||= Guild.find_by(id: guild_id, owner_id: current_user.id)
    unless @guild
      render json: { error: t("controllers.guilds.access_denied") }, status: :not_found
      return
    end
  end

  def require_can_manage_roles_for_discord_sync
    return unless @guild

    unless can_manage_roles?(@guild)
      render json: { error: t("controllers.guilds.permissions.roles_denied") }, status: :forbidden
    end
  end

  def check_discord_connected
    @discord_setting = @guild.guild_discord_setting
    @discord_guild_id = @discord_setting&.discord_guild_id
    
    unless @discord_setting&.connected? && @discord_guild_id.present?
      render json: { error: t("api.discord.not_connected") }, status: :unprocessable_entity
    end
  end

  def bot_token
    @discord_setting&.bot_token || ENV["DISCORD_BOT_TOKEN"]
  end
end

