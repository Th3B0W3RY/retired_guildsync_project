# frozen_string_literal: true

class ReactRolesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :load_and_authorize_guild

  # PATCH /guilds/:id/react_roles
  # Upserts all 3 react role slots from the submitted form.
  def update
    channel_id = params[:channel_id].presence

    ActiveRecord::Base.transaction do
      submitted_positions = []

      Array(params[:react_roles]).each do |rr_params|
        position   = rr_params[:position].to_i
        role_id    = rr_params[:role_id].presence
        role_name  = rr_params[:role_name].presence
        emoji_name = rr_params[:emoji_name].presence
        emoji_id   = rr_params[:emoji_id].presence
        is_custom  = rr_params[:is_custom_emoji].in?([ true, "true", "1" ])

        next unless position.in?(1..3) && role_id.present? && emoji_name.present?

        submitted_positions << position

        react_role = @guild.react_roles.find_or_initialize_by(position: position)
        react_role.assign_attributes(
          role_id: role_id,
          role_name: role_name || role_id,
          emoji_name: emoji_name,
          emoji_id: emoji_id,
          is_custom_emoji: is_custom,
          channel_id: channel_id
        )
        react_role.save!
      end

      # Remove positions that were cleared / not included in the submission
      @guild.react_roles.where.not(position: submitted_positions).destroy_all
    end

    render json: { success: true, message: t("controllers.react_roles.saved") }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # POST /guilds/:id/react_roles/deploy
  # Deploys (or updates) the embed message to Discord.
  def deploy
    if @guild.react_roles.empty?
      redirect_to guild_settings_path(@guild), alert: t("controllers.react_roles.no_roles_configured")
      return
    end

    if @guild.react_roles.first.channel_id.blank?
      redirect_to guild_settings_path(@guild), alert: t("controllers.react_roles.no_channel_configured")
      return
    end

    DiscordReactRolesService.new(@guild).deploy_embed
    redirect_to guild_settings_path(@guild), notice: t("controllers.react_roles.deployed")
  rescue => e
    Rails.logger.error "[ReactRoles] deploy failed for guild #{@guild.id}: #{e.class}: #{e.message}"
    redirect_to guild_settings_path(@guild), alert: t("controllers.react_roles.deploy_failed")
  end

  # DELETE /guilds/:id/react_roles
  # Removes the Discord embed and destroys all ReactRole records for this guild.
  def destroy
    DiscordReactRolesService.new(@guild).remove_embed if @guild.react_roles.any?
    @guild.react_roles.destroy_all
    redirect_to guild_settings_path(@guild), notice: t("controllers.react_roles.removed")
  rescue => e
    Rails.logger.error "[ReactRoles] destroy failed for guild #{@guild.id}: #{e.class}: #{e.message}"
    redirect_to guild_settings_path(@guild), alert: t("controllers.react_roles.remove_failed")
  end

  # GET /guilds/:id/react_roles/emojis
  # Returns the guild's custom Discord emojis as JSON for the emoji picker.
  def emojis
    discord_guild_id = @guild.discord_id.presence || @guild.guild_discord_setting&.discord_guild_id
    emojis = discord_guild_id.present? ? DiscordService.new.get_guild_emojis(discord_guild_id) : []
    render json: emojis
  rescue => e
    Rails.logger.error "[ReactRoles] emojis fetch failed for guild #{@guild.id}: #{e.class}: #{e.message}"
    render json: []
  end

  private

  def load_and_authorize_guild
    @guild = current_user.guilds.find_by(id: params[:id]) ||
             Guild.joins(:guild_members)
                  .where(guild_members: { user_id: current_user.id })
                  .find_by(id: params[:id])

    unless @guild
      render json: { error: t("controllers.guilds.not_found") }, status: :not_found
      return
    end

    unless can_manage_guild_settings?(@guild)
      render json: { error: t("api.v1.not_authorized") }, status: :forbidden
      return
    end
  end
end
