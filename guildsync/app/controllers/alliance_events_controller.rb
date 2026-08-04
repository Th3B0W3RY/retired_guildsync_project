# frozen_string_literal: true

class AllianceEventsController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include AllianceNestedAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :set_alliance
  before_action :require_alliance_member
  before_action :set_event, only: [ :show, :edit, :update, :destroy, :rsvp ]
  before_action :require_can_manage, only: [ :new, :create, :edit, :update, :destroy ]

  def index
    preserve_session
    @upcoming_events = @alliance.alliance_events.upcoming
    @past_events     = @alliance.alliance_events.past.limit(20)
  end

  def show
    preserve_session
    @my_participation = @event.alliance_event_participations.find_by(user: current_user)
    @participants     = @event.alliance_event_participations.includes(:user)
  end

  def new
    preserve_session
    @event = @alliance.alliance_events.build
  end

  def create
    preserve_session
    @event = @alliance.alliance_events.build(event_params)
    @event.created_by = current_user

    if @event.save
      AllianceDiscordBroadcastService.broadcast_alliance_event_created(@alliance, @event)
      AllianceActivityLogger.log(
        alliance: @alliance,
        user: current_user,
        guild: current_user_guild_for_log,
        action_type: "alliance_event_created",
        description: %(Alliance event "#{@event.title}" was created),
        title: @event.title,
        **AllianceActivityLogger.guild_context_metadata(current_user_guild_for_log)
      )
      redirect_to alliance_alliance_event_path(@alliance, @event), notice: t("alliances.events.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    preserve_session
  end

  def update
    preserve_session
    if @event.update(event_params)
      AllianceDiscordBroadcastService.broadcast_alliance_event_updated(@event)
      AllianceActivityLogger.log(
        alliance: @alliance,
        user: current_user,
        guild: current_user_guild_for_log,
        action_type: "alliance_event_updated",
        description: %(Alliance event "#{@event.title}" was updated),
        title: @event.title,
        **AllianceActivityLogger.guild_context_metadata(current_user_guild_for_log)
      )
      redirect_to alliance_alliance_event_path(@alliance, @event), notice: t("alliances.events.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    preserve_session
    title = @event.title
    AllianceDiscordBroadcastService.broadcast_alliance_event_deleted(@event)
    AllianceActivityLogger.log(
      alliance: @alliance,
      user: current_user,
      guild: current_user_guild_for_log,
      action_type: "alliance_event_deleted",
      description: %(Alliance event "#{title}" was deleted),
      title: title,
      **AllianceActivityLogger.guild_context_metadata(current_user_guild_for_log)
    )
    @event.soft_delete!
    redirect_to alliance_alliance_events_path(@alliance), notice: t("alliances.events.deleted")
  end

  def rsvp
    preserve_session
    status = params[:status]&.to_sym
    unless AllianceEventParticipation.statuses.key?(status.to_s)
      redirect_to alliance_alliance_event_path(@alliance, @event), alert: t("alliances.events.errors.invalid_rsvp")
      return
    end

    participation = @event.alliance_event_participations.find_or_initialize_by(user: current_user)
    participation.status = status
    participation.save!

    redirect_to alliance_alliance_event_path(@alliance, @event), notice: t("alliances.events.rsvp_saved")
  end

  private

  def set_event
    @event = @alliance.alliance_events.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to alliance_alliance_events_path(@alliance), alert: t("alliances.events.errors.not_found")
  end

  def require_can_manage
    return if alliance_owner_in_active_guild?(@alliance)

    redirect_to alliance_alliance_events_path(@alliance), alert: t("alliances.events.errors.manage_unauthorized")
  end

  def current_user_guild_for_log
    @current_user_guild_for_log ||= @alliance.alliance_members.find_by(user: current_user, status: :active)&.guild
  end

  def event_params
    p = params.require(:alliance_event).permit(
      :title, :description, :scheduled_at, :duration, :location, :event_type, :status,
      :max_participants, :squad_leader,
      role_categories: []
    )
    p[:role_categories] = p[:role_categories].compact_blank if p[:role_categories]
    p
  end

  def preserve_session
    return unless user_signed_in? && current_user.present?
    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end
