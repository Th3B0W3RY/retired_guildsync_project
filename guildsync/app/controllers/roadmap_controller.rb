# frozen_string_literal: true

class RoadmapController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index, :show ]
  skip_before_action :require_mfa_if_enabled, only: [ :index, :show ]
  skip_before_action :ensure_fully_authenticated, only: [ :index, :show ]
  skip_before_action :check_credentials_setup_required, only: [ :index, :show ]
  skip_before_action :validate_session, only: [ :index, :show ]

  def index
    @search = params[:q].to_s.strip
    scope = FeatureRequest.visible_to_public.for_list

    if @search.present?
      term = "%#{sanitize_search_input(@search)}%"
      scope = scope.where(
        "title ILIKE :term OR description ILIKE :term",
        term: term
      )
    end

    @by_status = FeatureRequest::STATUSES.index_with do |status|
      scope.by_status(status).to_a
    end
    @by_status["popular"] = scope.popular.for_list.to_a

    respond_to do |format|
      format.html
      format.json { render json: roadmap_json(@by_status) }
    end
  end

  def create
    unless user_signed_in?
      respond_to do |format|
        format.html { redirect_to login_path, alert: t("roadmap.create.sign_in_required") }
        format.turbo_stream { redirect_to login_path, alert: t("roadmap.create.sign_in_required"), status: :see_other }
        format.json { render json: { error: t("roadmap.create.sign_in_required") }, status: :unauthorized }
      end
      return
    end

    @feature_request = current_user.feature_requests.build(feature_request_params)
    @feature_request.status = "considering"
    @feature_request.title = sanitize_text_input(@feature_request.title)
    @feature_request.description = sanitize_text_input(@feature_request.description)

    if @feature_request.save
      @roadmap_stream_append_card = @feature_request.visible? && feature_request_matches_active_search?(@feature_request)
      pending_review = @feature_request.moderation_status == "pending"
      notice_key = pending_review ? "roadmap.create.sent_for_review" : "roadmap.create.success"
      message = t(notice_key)
      respond_to do |format|
        format.html { redirect_to roadmap_path, notice: message }
        format.turbo_stream
        format.json { render json: { id: @feature_request.id, message: message, moderation_status: @feature_request.moderation_status }, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to roadmap_path, alert: @feature_request.errors.full_messages.to_sentence }
        format.turbo_stream { render_roadmap_create_form_error(@feature_request.errors.full_messages.to_sentence) }
        format.json { render json: { errors: @feature_request.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def vote
    unless user_signed_in?
      render json: { error: t("roadmap.vote.sign_in_required") }, status: :unauthorized
      return
    end

    request_record = FeatureRequest.visible_to_public.find_by(id: params[:id])
    unless request_record
      render json: { error: t("roadmap.vote.not_found") }, status: :not_found
      return
    end

    vote_record = request_record.feature_request_votes.find_by(user_id: current_user.id)
    if vote_record
      vote_record.destroy!
      request_record.decrement!(:vote_count)
      voted = false
    else
      request_record.feature_request_votes.create!(user: current_user)
      request_record.increment!(:vote_count)
      voted = true
    end

    render json: {
      vote_count: request_record.reload.vote_count,
      voted: voted
    }
  end

  def show
    @feature_request = FeatureRequest.visible_to_public.find_by(id: params[:id])
    unless @feature_request
      respond_to do |format|
        format.html { redirect_to roadmap_path, alert: t("roadmap.not_found") }
        format.json { render json: { error: t("roadmap.not_found") }, status: :not_found }
      end
      return
    end
    @comments = @feature_request.feature_request_comments.visible_to_public.chronological
  end

  def create_comment
    unless user_signed_in?
      respond_to do |format|
        format.html { redirect_to login_path, alert: t("roadmap.comments.sign_in_required") }
        format.turbo_stream { redirect_to login_path, alert: t("roadmap.comments.sign_in_required"), status: :see_other }
        format.json { render json: { error: t("roadmap.comments.sign_in_required") }, status: :unauthorized }
      end
      return
    end

    @feature_request = FeatureRequest.visible_to_public.find_by(id: params[:id])
    unless @feature_request
      respond_to do |format|
        format.html { redirect_to roadmap_path, alert: t("roadmap.comments.not_found") }
        format.turbo_stream { redirect_to roadmap_path, alert: t("roadmap.comments.not_found"), status: :see_other }
        format.json { render json: { error: t("roadmap.comments.not_found") }, status: :not_found }
      end
      return
    end

    body = sanitize_text_input(params[:body].to_s)
    if body.blank?
      respond_to do |format|
        format.html { redirect_to roadmap_feature_request_path(@feature_request), alert: t("roadmap.comments.empty") }
        format.turbo_stream { render_roadmap_comment_form_error(t("roadmap.comments.empty")) }
        format.json { render json: { errors: [ t("roadmap.comments.empty") ] }, status: :unprocessable_entity }
      end
      return
    end

    @comment = @feature_request.feature_request_comments.build(user: current_user, body: body)
    if @comment.save
      pending_review = @comment.moderation_status == "pending"
      notice_key = pending_review ? "roadmap.comments.sent_for_review" : "roadmap.comments.created"
      respond_to do |format|
        format.html { redirect_to roadmap_feature_request_path(@feature_request), notice: t(notice_key) }
        format.turbo_stream
        format.json { render json: comment_json(@comment).merge(moderation_status: @comment.moderation_status), status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to roadmap_feature_request_path(@feature_request), alert: @comment.errors.full_messages.to_sentence }
        format.turbo_stream { render_roadmap_comment_form_error(@comment.errors.full_messages.to_sentence) }
        format.json { render json: { errors: @comment.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy_comment
    unless user_signed_in?
      respond_to do |format|
        format.json { render json: { error: t("roadmap.comments.sign_in_required") }, status: :unauthorized }
        format.turbo_stream { redirect_to login_path, alert: t("roadmap.comments.sign_in_required"), status: :see_other }
      end
      return
    end

    @comment = FeatureRequestComment.find_by(id: params[:id])
    unless @comment
      respond_to do |format|
        format.json { render json: { error: t("roadmap.comments.not_found") }, status: :not_found }
        format.turbo_stream { render_roadmap_comment_form_error(t("roadmap.comments.not_found"), status: :not_found) }
      end
      return
    end

    unless @comment.can_delete_by?(current_user)
      respond_to do |format|
        format.json { render json: { error: t("roadmap.comments.cannot_delete") }, status: :forbidden }
        format.turbo_stream { render_roadmap_comment_form_error(t("roadmap.comments.cannot_delete"), status: :forbidden) }
      end
      return
    end

    @comment.soft_delete!
    @feature_request = @comment.feature_request

    respond_to do |format|
      format.json { render json: { ok: true } }
      format.turbo_stream
    end
  end

  private

  def render_roadmap_comment_form_error(message, status: :unprocessable_entity)
    render turbo_stream: turbo_stream.update(
      "roadmap_comment_form_errors",
      helpers.tag.p(message, class: "text-xs text-red-400")
    ), status: status
  end

  def render_roadmap_create_form_error(message)
    render turbo_stream: turbo_stream.update(
      "roadmap_modal_form_errors",
      helpers.tag.p(message, class: "text-sm text-red-400")
    ), status: :unprocessable_entity
  end

  def feature_request_matches_active_search?(fr)
    q = params[:q].to_s.strip
    return true if q.blank?

    term = "%#{sanitize_search_input(q)}%"
    FeatureRequest.where(id: fr.id).where(
      "title ILIKE :term OR description ILIKE :term",
      term: term
    ).exists?
  end

  def feature_request_params
    params.require(:feature_request).permit(:title, :description)
  end

  def roadmap_json(by_status)
    by_status.transform_values do |list|
      list.map { |fr| feature_request_json(fr) }
    end
  end

  def feature_request_json(fr)
    {
      id: fr.id,
      title: fr.title,
      description: fr.description,
      status: fr.status,
      vote_count: fr.vote_count,
      anonymized_requester: fr.anonymized_requester_name,
      created_at: fr.created_at.iso8601,
      is_pinned: fr.is_pinned,
      release_note_url: fr.release_note_url,
      voted: user_signed_in? && fr.voted_by?(current_user)
    }
  end

  def comment_json(c)
    {
      id: c.id,
      body: c.body,
      anonymized_author: c.anonymized_author_name,
      created_at: c.created_at.iso8601,
      can_delete: user_signed_in? && c.can_delete_by?(current_user)
    }
  end
end
