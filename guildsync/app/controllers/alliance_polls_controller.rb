# frozen_string_literal: true

class AlliancePollsController < ApplicationController
  include RequiresPaidPlanForAllianceFeatures
  include AllianceActivityViewLogging
  include AllianceNestedAccess

  before_action :authenticate_user!
  before_action :require_mfa_if_enabled
  before_action :require_paid_plan_for_alliance_features
  before_action :set_alliance
  before_action :require_alliance_member
  before_action :set_poll, only: [ :show, :destroy, :vote ]
  before_action :require_can_manage, only: [ :new, :create, :destroy ]

  def index
    preserve_session
    @polls = @alliance.alliance_polls.ordered.includes(alliance_poll_votes: :user)
  end

  def show
    preserve_session
    @current_user_vote  = @poll.user_vote(current_user)
    @vote_counts        = @poll.vote_counts
    @vote_percentages   = @poll.vote_percentages
    @voters_by_choice   = @poll.voters_display_names_by_choice
  end

  def new
    preserve_session
    @poll = @alliance.alliance_polls.build
  end

  def create
    preserve_session
    @poll = @alliance.alliance_polls.build(poll_params)
    @poll.creator = current_user

    if @poll.save
      AllianceDiscordBroadcastService.broadcast_alliance_poll_created(@alliance, @poll)
      redirect_to alliance_alliance_poll_path(@alliance, @poll), notice: t("alliances.polls.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    preserve_session
    @poll.soft_delete!
    redirect_to alliance_alliance_polls_path(@alliance), notice: t("alliances.polls.deleted")
  end

  def vote
    preserve_session
    unless @poll.open?
      render json: { error: t("alliances.polls.errors.poll_closed") }, status: :unprocessable_entity
      return
    end

    choice = params[:choice]&.to_i
    unless AlliancePollVote.choices.values.include?(choice)
      render json: { error: t("alliances.polls.errors.invalid_choice") }, status: :unprocessable_entity
      return
    end

    poll_vote = @poll.alliance_poll_votes.find_or_initialize_by(user: current_user)
    poll_vote.choice = choice

    if poll_vote.save
      begin
        DiscordAlliancePollService.update_all_linked_messages(@poll.reload)
      rescue StandardError => e
        Rails.logger.warn "[AlliancePollsController#vote] Discord update failed: #{e.class}: #{e.message}"
      end

      @poll.reload
      AlliancePollsChannel.broadcast_vote_update(@poll)

      payload = {
        success:          true,
        vote_counts:      @poll.vote_counts,
        vote_percentages: @poll.vote_percentages,
        user_vote:        choice
      }
      payload[:voters_by_choice] = @poll.voters_display_names_by_choice unless @poll.anonymous?

      render json: payload
    else
      render json: { error: poll_vote.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def set_poll
    @poll = @alliance.alliance_polls.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to alliance_alliance_polls_path(@alliance), alert: t("alliances.polls.errors.not_found")
  end

  def require_can_manage
    return if can_manage_alliance_actions?(@alliance)

    redirect_to alliance_alliance_polls_path(@alliance), alert: t("alliances.polls.errors.manage_unauthorized")
  end

  def poll_params
    params.require(:alliance_poll).permit(:title, :description, :deadline, :anonymous)
  end

  def preserve_session
    return unless user_signed_in? && current_user.present?
    session[:user_id] = current_user.id
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end
