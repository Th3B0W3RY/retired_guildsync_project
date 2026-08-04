# frozen_string_literal: true

class JoinController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :show ]
  skip_before_action :require_mfa_if_enabled, only: [ :show ]
  skip_before_action :ensure_fully_authenticated, only: [ :show ]
  skip_before_action :validate_session, only: [ :show ]

  # GET /join/:token — public; show "sign in or create account to join this guild"
  def show
    @link = GuildInviteLink.find_by_token(params[:token])
    if @link.blank? || @link.expired?
      @link&.destroy if @link&.expired?
      render :invalid, status: :not_found
      return
    end
    session[:pending_guild_invite_token] = @link.token
    @guild = @link.guild
    # If already fully signed in, complete the join immediately
    if user_signed_in? && current_user.present? && mfa_verified_for_session?
      redirect_to join_complete_path
      return
    end
    render :show
  end

  # GET /join/complete — requires auth; consume token, add user to guild, redirect
  def complete
    token = session[:pending_guild_invite_token]
    session.delete(:pending_guild_invite_token)
    link = GuildInviteLink.find_by_token(token) if token.present?
    if link.blank? || link.expired?
      link&.destroy if link&.expired?
      redirect_to dashboard_path, alert: t("join.invalid_or_used")
      return
    end
    guild = link.guild
    if conflicting_alliance_membership?(guild, current_user)
      redirect_to dashboard_path, alert: t("join.conflicting_alliance")
      return
    end
    if guild.guild_members.exists?(user_id: current_user.id)
      link.destroy
      redirect_to guild_path(guild), notice: t("join.already_member", name: guild.name)
      return
    end
    unless add_user_to_guild_with_default_role(guild, current_user)
      redirect_to dashboard_path, alert: t("compliance.ip_conflict.warning_message")
      return
    end
    link.destroy
    redirect_to guild_path(guild), notice: t("join.welcome", name: guild.name)
  end

  private

  def conflicting_alliance_membership?(guild, user)
    ag = guild.alliance_guild
    return false unless ag&.active?

    user.alliance_members.active_members.where.not(alliance_id: ag.alliance_id).exists?
  end

  def add_user_to_guild_with_default_role(guild, user)
    member = guild.guild_members.create(
      user: user,
      role: :member,
      status: :active,
      discord_role_id: guild.default_role_id
    )
    return false unless member.persisted?

    apply_discord_default_role(guild, user) if guild.default_role_id.present?
    true
  end

  def apply_discord_default_role(guild, user)
    return unless guild.guild_discord_setting&.connected?
    return unless user.user_discord_connection&.discord_user_id.present?

    discord_service = DiscordService.new
    discord_guild_id = guild.guild_discord_setting.discord_guild_id
    discord_user_id = user.user_discord_connection.discord_user_id
    discord_member = discord_service.get_guild_member(discord_guild_id, discord_user_id)
    current_discord_roles = discord_member&.dig("roles") || []
    return if current_discord_roles.include?(guild.default_role_id)

    discord_service.add_role_to_member(discord_guild_id, discord_user_id, guild.default_role_id)
  rescue => e
    Rails.logger.error "Failed to apply default Discord role: #{e.message}"
  end
end
