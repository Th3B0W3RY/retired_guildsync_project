# frozen_string_literal: true

class AllianceJoinRequestsController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include AllianceNestedAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :set_alliance
  before_action :set_join_request, only: [ :accept, :decline ]
  before_action :require_can_manage_join_requests, only: [ :index, :accept, :decline ]
  before_action :require_requesting_owner_paid_when_accepting_join, only: [ :accept ]

  def index
    preserve_session
    @pending = @alliance.alliance_join_requests.pending_requests.includes(:requesting_guild, :requested_by_user).order(created_at: :desc)
  end

  def create
    preserve_session
    requesting_guild = current_user.owned_guilds.find_by(id: params[:requesting_guild_id])

    unless requesting_guild
      redirect_to dashboard_path, alert: t("alliances.join_requests.errors.guild_not_found")
      return
    end

    unless requesting_guild.owner_id == current_user.id
      redirect_to guild_path(requesting_guild), alert: t("alliances.join_requests.errors.unauthorized")
      return
    end

    if requesting_guild.alliance_guild&.active?
      redirect_to guild_path(requesting_guild), alert: t("alliances.join_requests.errors.already_in_alliance")
      return
    end

    unless @alliance.active?
      redirect_to new_guild_alliance_join_request_path(requesting_guild), alert: t("alliances.join_requests.errors.alliance_inactive")
      return
    end

    unless @alliance.can_add_more_guilds?
      redirect_to new_guild_alliance_join_request_path(requesting_guild), alert: t("alliances.join_requests.errors.max_guilds")
      return
    end

    if AllianceInvite.exists?(alliance_id: @alliance.id, guild_id: requesting_guild.id, status: :pending)
      redirect_to new_guild_alliance_join_request_path(requesting_guild), alert: t("alliances.join_requests.errors.pending_invite")
      return
    end

    join_request = @alliance.alliance_join_requests.build(
      requesting_guild:   requesting_guild,
      requested_by_user:  current_user,
      status:             :pending
    )

    if join_request.save
      AllianceDiscordBroadcastService.notify_join_request_created(join_request)
      redirect_to guild_path(requesting_guild), notice: t("alliances.join_requests.created", alliance_name: @alliance.name)
    else
      redirect_to new_guild_alliance_join_request_path(requesting_guild),
                  alert: join_request.errors.full_messages.join(", ").presence || t("alliances.join_requests.errors.create_failed")
    end
  end

  def accept
    preserve_session
    if @join_request.accept!(current_user)
      redirect_to alliance_alliance_join_requests_path(@alliance), notice: t("alliances.join_requests.accepted", guild_name: @join_request.requesting_guild.name)
    else
      msg = @join_request.errors.full_messages.join(", ").presence || t("alliances.join_requests.errors.accept_failed")
      redirect_to alliance_alliance_join_requests_path(@alliance), alert: msg
    end
  end

  def decline
    preserve_session
    @join_request.decline!
    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: @join_request.requesting_guild,
      action_type: "alliance_join_request_declined",
      description: %(Join request from "#{@join_request.requesting_guild.name}" was declined),
      target_name: @join_request.requesting_guild.name,
      **AllianceActivityLogger.guild_context_metadata(@join_request.requesting_guild)
    )
    redirect_to alliance_alliance_join_requests_path(@alliance), notice: t("alliances.join_requests.declined")
  end

  private

  def set_join_request
    @join_request = @alliance.alliance_join_requests.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to alliance_alliance_join_requests_path(@alliance), alert: t("alliances.join_requests.errors.not_found")
  end

  def require_can_manage_join_requests
    return if gm_or_officer_guild_for_alliance

    redirect_to alliance_path(@alliance), alert: t("alliances.join_requests.errors.manage_unauthorized")
  end

  def gm_or_officer_guild_for_alliance
    current_user.owned_guilds.find do |guild|
      @alliance.active_guild_ids.include?(guild.id)
    end || begin
      officer_member = @alliance.alliance_members.find_by(user: current_user, role: :officer, status: :active)
      officer_member&.guild
    end
  end

  def require_requesting_owner_paid_when_accepting_join
    owner = @join_request.requesting_guild.owner
    return unless owner.blocked_from_alliance_features?

    redirect_to alliance_alliance_join_requests_path(@alliance),
                alert: t("alliances.errors.join_requires_paid_plan") and return
  end

  def require_paid_plan_for_all_alliance_actions?
    true
  end

  def alliance_features_plan_blocked_redirect_path
    gid = params[:requesting_guild_id].presence
    if gid && (g = current_user.owned_guilds.find_by(id: gid))
      guild_path(g)
    else
      super
    end
  end

  def preserve_session
    return unless user_signed_in? && current_user.present?
    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end
