# frozen_string_literal: true

class AlliancesController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include UiPagination

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :require_paid_plan_for_alliance_guild_search, only: [ :guild_search ]
  before_action :set_alliance, only: [ :show, :edit, :update, :destroy, :leave, :kick_guild ]
  before_action :require_alliance_member, only: [ :show ]
  before_action :require_alliance_leader, only: [ :edit, :update ]
  before_action :require_can_manage_invites_or_kicks, only: [ :kick_guild ]

  def index
    preserve_session
    @alliance_member = current_user.alliance_members.where(status: :active).includes(:alliance).first
    @alliance = @alliance_member&.alliance
  end

  def guild_search
    preserve_session
    return head :forbidden if params[:guild_id].blank?

    unless current_user.owned_guilds.exists?(id: params[:guild_id])
      return head :forbidden
    end

    query = sanitize_search_input(params[:q])
    page = ui_page_param(:page)
    per_page = ui_per_page_param(default: 15, max: 50)
    if query.blank?
      return render json: {
        results: [],
        pagination: ui_pagination_hash(page: 1, per_page: per_page, total_count: 0)
      }
    end

    base = Guild
      .publicly_listed
      .joins(:owner)
      .where(
        "guilds.name ILIKE :q OR guilds.description ILIKE :q OR users.username ILIKE :q",
        q: "%#{query}%"
      )
      .order("guilds.name ASC", "guilds.id ASC")

    total_count = base.count
    rows = base.offset((page - 1) * per_page).limit(per_page)

    render json: {
      results: rows.map { |g|
        ag = g.alliance_guild
        {
          id: g.id,
          name: g.name,
          alliance_id: (ag&.active? ? ag.alliance_id : nil),
          alliance_name: (ag&.active? ? ag.alliance.name : nil)
        }
      },
      pagination: ui_pagination_hash(page: page, per_page: per_page, total_count: total_count)
    }
  end

  def show
    preserve_session
    @alliance_guild  = @alliance.alliance_guilds.where(status: :active).includes(:guild).to_a
    @alliance_members = @alliance.alliance_members.where(status: :active).includes(:user, :guild).order(:role)
    @pending_invites  = @alliance.alliance_invites.where(status: :pending).includes(:guild) if can_manage_alliance_for_current_user?
    @current_member   = @alliance.alliance_members.find_by(user: current_user, status: :active)
    @disband_vote     = @alliance.alliance_disband_votes.find_by(guild_id: current_user_guild_in_alliance&.id)
  end

  def new
    preserve_session
    @guild = eligible_guild_for_new_alliance
    unless @guild
      redirect_to dashboard_path, alert: t("alliances.errors.no_eligible_guild")
      return
    end

    unless current_user_plan_allows_alliance?
      redirect_to upgrade_pricing_path, alert: t("alliances.errors.plan_required")
      return
    end

    @alliance = Alliance.new
  end

  def create
    preserve_session
    @guild = eligible_guild_for_new_alliance
    unless @guild
      redirect_to dashboard_path, alert: t("alliances.errors.no_eligible_guild")
      return
    end

    unless current_user_plan_allows_alliance?
      redirect_to upgrade_pricing_path, alert: t("alliances.errors.plan_required")
      return
    end

    @alliance = Alliance.new(alliance_params)
    @alliance.leader_guild = @guild
    @alliance.leader_user  = current_user

    if @alliance.save
      AllianceGuild.create!(
        alliance:          @alliance,
        guild:             @guild,
        status:            :active,
        joined_at:         Time.current,
        invited_by_user:   current_user
      )
      AllianceMemberSyncService.new(@alliance, @guild).sync!
      AllianceActivityLogger.log(
        alliance: @alliance,
        user: current_user,
        guild: @guild,
        action_type: "alliance_created",
        description: %(Alliance "#{@alliance.name}" was created),
        **AllianceActivityLogger.guild_context_metadata(@guild)
      )
      redirect_to alliance_path(@alliance), notice: t("alliances.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    preserve_session
  end

  def update
    preserve_session
    if @alliance.update(alliance_params)
      redirect_to alliance_path(@alliance), notice: t("alliances.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    preserve_session
    unless can_disband_alliance? && (@alliance.leader_user == current_user || gm_in_alliance?)
      redirect_to alliance_path(@alliance), alert: t("alliances.errors.disband_unauthorized")
      return
    end

    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: @alliance.leader_guild,
      action_type: "alliance_disbanded",
      description: %(Alliance "#{@alliance.name}" was disbanded),
      **AllianceActivityLogger.guild_context_metadata(@alliance.leader_guild)
    )
    @alliance.disband!
    redirect_to dashboard_path, notice: t("alliances.disbanded")
  end

  def leave
    preserve_session
    my_guild = current_user_guild_in_alliance
    unless my_guild && my_guild.owner == current_user
      redirect_to alliance_path(@alliance), alert: t("alliances.errors.leave_unauthorized")
      return
    end

    if @alliance.leader_guild == my_guild
      redirect_to alliance_path(@alliance), alert: t("alliances.errors.leader_cannot_leave")
      return
    end

    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: my_guild,
      action_type: "guild_left_alliance",
      description: %(#{my_guild.name} left the alliance),
      target_name: my_guild.name,
      **AllianceActivityLogger.guild_context_metadata(my_guild)
    )
    remove_guild_from_alliance(my_guild, :left)
    redirect_to dashboard_path, notice: t("alliances.left")
  end

  def kick_guild
    preserve_session
    guild_to_kick = Guild.find_by(id: params[:guild_id])
    unless guild_to_kick && @alliance.active_guild_ids.include?(guild_to_kick.id)
      redirect_to alliance_path(@alliance), alert: t("alliances.errors.guild_not_found")
      return
    end

    if guild_to_kick == @alliance.leader_guild
      redirect_to alliance_path(@alliance), alert: t("alliances.errors.cannot_kick_leader_guild")
      return
    end

    remove_guild_from_alliance(guild_to_kick, :kicked)
    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: guild_to_kick,
      action_type: "guild_kicked_from_alliance",
      description: %(#{guild_to_kick.name} was removed from the alliance),
      target_name: guild_to_kick.name,
      **AllianceActivityLogger.guild_context_metadata(guild_to_kick)
    )
    redirect_to alliance_path(@alliance), notice: t("alliances.guild_kicked")
  end

  private

  # Guild search from the hub requires a non-free plan with active access (same as alliance gate).
  def require_paid_plan_for_alliance_guild_search
    return unless current_user.blocked_from_alliance_features?

    head :forbidden
  end

  def set_alliance
    @alliance = Alliance.find_by(id: params[:id])
    unless @alliance
      redirect_to dashboard_path, alert: t("controllers.guilds.access_denied")
      return
    end
  end

  def require_alliance_member
    return if @alliance.alliance_members.where(user: current_user, status: :active).exists?

    redirect_to dashboard_path, alert: t("controllers.guilds.access_denied")
  end

  def require_alliance_leader
    unless @alliance.leader_user == current_user
      redirect_to alliance_path(@alliance), alert: t("alliances.errors.not_leader")
    end
  end

  def require_can_manage_invites_or_kicks
    return if can_kick_alliance_actions?(@alliance)

    redirect_to alliance_path(@alliance), alert: t("alliances.errors.kick_unauthorized")
  end

  def alliance_params
    params.require(:alliance).permit(:name, :description, :logo)
  end

  def eligible_guild_for_new_alliance
    eligible_guilds_for_alliance.first
  end

  # Only guild **owners** may create an alliance (not officers with can_manage_alliance).
  def eligible_guilds_for_alliance
    current_user.owned_guilds.includes(:alliance_guild).select { |guild| guild.alliance_guild.nil? }
  end

  # Alliances where the user may accept/decline join requests (same idea as alliance invite permissions).
  def managed_alliance_ids
    current_user.alliance_members.where(status: :active).includes(:alliance, :guild).filter_map do |am|
      a = am.alliance
      next unless a&.active?
      g = am.guild
      next unless g
      next unless a.leader_user_id == current_user.id || can_manage_alliance?(g)

      a.id
    end.uniq
  end

  def current_user_plan_allows_alliance?
    plan = current_user.current_plan
    plan&.can_create_alliance?
  end

  def current_user_guild_in_alliance
    my_guild_ids = current_user.owned_guilds.pluck(:id)
    @alliance.alliance_guilds.where(status: :active, guild_id: my_guild_ids).first&.guild
  end

  def can_disband_alliance?
    return true if @alliance.leader_user == current_user
    gm_in_alliance? && @alliance.majority_voted_to_disband?
  end

  def can_manage_alliance_for_current_user?
    my_guild = current_user_guild_in_alliance
    return true if @alliance.leader_user == current_user
    return false unless my_guild
    can_invite_alliance_guilds?(my_guild) || can_kick_alliance_guilds?(my_guild)
  end

  def gm_in_alliance?
    current_user_guild_in_alliance.present?
  end

  def remove_guild_from_alliance(guild, status_sym)
    AllianceGuild.transaction do
      ag = @alliance.alliance_guilds.find_by(guild_id: guild.id)
      ag&.update!(status: status_sym)
      @alliance.alliance_members.where(guild_id: guild.id, status: :active)
              .update_all(status: AllianceMember.statuses[:removed])
    end

    @alliance.reload
    if @alliance.active_guild_count < 1
      @alliance.disband!
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
