# frozen_string_literal: true

# Guild owner: pending alliance invites sent to this guild (accept/decline).
class GuildAllianceInvitesController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include RequiresActiveGuildAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :set_guild
  before_action :require_active_guild_access
  before_action :require_guild_owner!
  before_action :require_paid_plan_for_alliance_features

  def pending
    preserve_session
    @pending_invites = AllianceInvite.where(guild_id: @guild.id, status: :pending)
                                     .includes(:alliance, :invited_by_user)
                                     .order(created_at: :desc)
  end

  private

  def set_guild
    guild_id = params[:guild_id]
    @guild = current_user.guilds.find_by(id: guild_id)
    @guild ||= current_user.owned_guilds.find_by(id: guild_id)
    @guild ||= Guild.find_by(id: guild_id, owner_id: current_user.id)

    return if @guild

    session.save if session.respond_to?(:save)
    redirect_to my_guilds_path, alert: t("controllers.guilds.access_denied")
  end

  def require_guild_owner!
    return if @guild.owner_id == current_user.id

    redirect_to dashboard_path, alert: t("alliances.invites.errors.accept_unauthorized")
  end

  def alliance_features_plan_blocked_redirect_path
    guild_path(@guild)
  end

  def require_paid_plan_for_all_alliance_actions?
    true
  end

  def preserve_session
    return unless user_signed_in? && current_user.present?
    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end
