# frozen_string_literal: true

class AllianceInvitesController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include UiPagination
  include AllianceNestedAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :set_alliance
  before_action :require_alliance_member, only: [ :index ]
  before_action :require_can_invite,      only: [ :create ]
  before_action :require_can_invite_json,  only: [ :guild_search ]
  before_action :set_invite, only: [ :accept, :decline ]

  def index
    preserve_session
    @pending_invites = @alliance.alliance_invites.where(status: :pending).includes(:guild, :invited_by_user)
    @can_invite = can_invite_alliance_actions?(@alliance)
  end

  # Publicly listed guilds whose **name** matches the query (invite UI). Leader-only; same permission as #create.
  def guild_search
    preserve_session
    query = sanitize_search_input(params[:q])
    page = ui_page_param(:page)
    per_page = ui_per_page_param(default: 20, max: 50)
    if query.blank?
      return render json: {
        results: [],
        pagination: ui_pagination_hash(page: 1, per_page: per_page, total_count: 0)
      }
    end

    active_ids = @alliance.active_guild_ids
    rel = Guild
      .publicly_listed
      .includes(:owner)
      .where("guilds.name ILIKE :q", q: "%#{query}%")
      .order("guilds.name ASC", "guilds.id ASC")
    rel = rel.where.not(id: active_ids) if active_ids.any?

    total_count = rel.count
    page_rows = rel.offset((page - 1) * per_page).limit(per_page)

    render json: {
      results: page_rows.map { |g|
        in_other_alliance = g.alliance_guild&.active?
        {
          id:               g.id,
          name:             g.name,
          owner_username:   g.owner.username,
          inviteable:       !in_other_alliance,
          in_other_alliance: in_other_alliance
        }
      },
      pagination: ui_pagination_hash(page: page, per_page: per_page, total_count: total_count)
    }
  end

  def create
    preserve_session
    target_guild = Guild.find_by(id: params[:guild_id])
    unless target_guild
      redirect_to alliance_alliance_invites_path(@alliance), alert: t("alliances.invites.errors.guild_not_found")
      return
    end

    if target_guild.alliance_guild&.active? || @alliance.alliance_guilds.where(guild_id: target_guild.id).exists?
      redirect_to alliance_alliance_invites_path(@alliance), alert: t("alliances.invites.errors.already_in_alliance")
      return
    end

    if @alliance.alliance_invites.where(guild_id: target_guild.id, status: :pending).exists?
      redirect_to alliance_alliance_invites_path(@alliance), alert: t("alliances.invites.errors.already_invited")
      return
    end

    if AllianceJoinRequest.exists?(alliance_id: @alliance.id, requesting_guild_id: target_guild.id, status: :pending)
      redirect_to alliance_alliance_invites_path(@alliance), alert: t("alliances.invites.errors.pending_join_request")
      return
    end

    unless @alliance.can_add_more_guilds?
      redirect_to alliance_alliance_invites_path(@alliance), alert: t("alliances.invites.errors.max_guilds")
      return
    end

    invite = @alliance.alliance_invites.create!(
      guild:            target_guild,
      invited_by_user:  current_user,
      status:           :pending
    )

    AllianceDiscordBroadcastService.notify_invite_created(invite)

    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: target_guild,
      action_type: "alliance_invite_sent",
      description: %(Invited guild "#{target_guild.name}" to the alliance),
      target_name: target_guild.name,
      **AllianceActivityLogger.guild_context_metadata(target_guild)
    )

    redirect_to alliance_alliance_invites_path(@alliance), notice: t("alliances.invites.sent", guild_name: target_guild.name)
  end

  def accept
    preserve_session
    unless @invite.guild.owner == current_user
      redirect_to dashboard_path, alert: t("alliances.invites.errors.accept_unauthorized")
      return
    end

    if @invite.guild.alliance_guild&.active?
      redirect_to dashboard_path, alert: t("alliances.invites.errors.already_in_alliance")
      return
    end

    @invite.accept!(current_user)
    AllianceDiscordBroadcastService.notify_guild_joined_alliance(@alliance, @invite.guild)
    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: @invite.guild,
      action_type: "alliance_invite_accepted",
      description: %(Guild "#{@invite.guild.name}" joined the alliance via invite),
      target_name: @invite.guild.name,
      **AllianceActivityLogger.guild_context_metadata(@invite.guild)
    )
    redirect_to invite_redirect_path, notice: t("alliances.invites.accepted", alliance_name: @alliance.name)
  end

  def decline
    preserve_session
    unless @invite.guild.owner == current_user
      redirect_to dashboard_path, alert: t("alliances.invites.errors.decline_unauthorized")
      return
    end

    @invite.decline!
    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: @invite.guild,
      action_type: "alliance_invite_declined",
      description: %(Invite for guild "#{@invite.guild.name}" was declined),
      target_name: @invite.guild.name,
      invite_response: true,
      **AllianceActivityLogger.guild_context_metadata(@invite.guild)
    )
    redirect_to invite_redirect_path, notice: t("alliances.invites.declined")
  end

  private

  def set_invite
    @invite = @alliance.alliance_invites.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: t("alliances.invites.errors.not_found")
  end

  def require_can_invite
    return if can_invite_alliance_actions?(@alliance)

    redirect_to alliance_path(@alliance), alert: t("alliances.invites.errors.invite_unauthorized")
  end

  def require_can_invite_json
    head :forbidden unless can_invite_alliance_actions?(@alliance)
  end

  def require_paid_plan_for_all_alliance_actions?
    true
  end

  def invite_redirect_path
    case params[:return_to].to_s
    when "hub"
      alliances_path
    when "guild"
      gid = params[:guild_id].presence || @invite&.guild_id
      gid.present? ? guild_path(gid) : dashboard_path
    else
      alliance_path(@alliance)
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
