# frozen_string_literal: true

module Admin
  class FeatureRequestsController < BaseController
    FEATURE_REQUESTS_INDEX_MAIN_FRAME = "admin_feature_requests_main"
    FEATURE_REQUESTS_EDIT_MAIN_FRAME = "admin_feature_requests_edit_main"

    before_action :set_feature_request, only: [ :edit, :update, :destroy, :pin, :move ]

    def index
      @search = params[:q].to_s.strip
      scope = FeatureRequest.all.for_list

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

      if request.headers["Turbo-Frame"] == FEATURE_REQUESTS_INDEX_MAIN_FRAME
        render "feature_requests_index_frame", layout: false
      end
    end

    def edit
      return render("feature_requests_edit_frame", layout: false) if request.headers["Turbo-Frame"] == FEATURE_REQUESTS_EDIT_MAIN_FRAME
    end

    def update
      if @feature_request.update(admin_feature_request_params)
        redirect_to admin_feature_requests_path, notice: t("roadmap.admin.updated")
      else
        redirect_to admin_feature_requests_path, alert: @feature_request.errors.full_messages.to_sentence
      end
    end

    def destroy
      @destroyed_feature_request_id = @feature_request.id
      @destroyed_column_status = @feature_request.status
      @feature_request.destroy!
      @destroy_notice = t("roadmap.admin.deleted")
      respond_to do |format|
        format.html { redirect_to admin_feature_requests_path, notice: @destroy_notice }
        format.turbo_stream
      end
    end

    def pin
      @feature_request.update!(is_pinned: !@feature_request.is_pinned)
      @pin_notice = @feature_request.is_pinned? ? t("roadmap.admin.pinned") : t("roadmap.admin.unpinned")
      respond_to do |format|
        format.html { redirect_to admin_feature_requests_path, notice: @pin_notice }
        format.turbo_stream
      end
    end

    def move
      new_status = params[:status].to_s
      unless FeatureRequest::STATUSES.include?(new_status)
        respond_to do |format|
          format.html { redirect_to admin_feature_requests_path, alert: t("roadmap.admin.invalid_status") }
          format.turbo_stream { render_admin_feature_requests_flash_alert(t("roadmap.admin.invalid_status")) }
          format.json { render json: { success: false, error: t("roadmap.admin.invalid_status") }, status: :unprocessable_entity }
        end
        return
      end

      old_status = @feature_request.status
      @move_notice = t("roadmap.admin.moved")

      if old_status == new_status
        respond_to do |format|
          format.html { redirect_to admin_feature_requests_path, notice: @move_notice }
          format.turbo_stream do
            @move_noop = true
            render :move
          end
          format.json do
            render json: {
              success: true,
              message: @move_notice,
              feature: { id: @feature_request.id, status: @feature_request.status }
            }
          end
        end
        return
      end

      target_was_empty = FeatureRequest.where(status: new_status).count.zero?

      if @feature_request.update(status: new_status)
        @old_status = old_status
        @new_status = new_status
        @target_was_empty = target_was_empty
        @move_noop = false
        respond_to do |format|
          format.html { redirect_to admin_feature_requests_path, notice: @move_notice }
          format.turbo_stream { render :move }
          format.json do
            render json: {
              success: true,
              message: @move_notice,
              feature: { id: @feature_request.id, status: @feature_request.status }
            }
          end
        end
      else
        respond_to do |format|
          format.html { redirect_to admin_feature_requests_path, alert: @feature_request.errors.full_messages.to_sentence }
          format.turbo_stream { render_admin_feature_requests_flash_alert(@feature_request.errors.full_messages.to_sentence) }
          format.json do
            render json: { success: false, errors: @feature_request.errors.full_messages }, status: :unprocessable_entity
          end
        end
      end
    end

    def reorder
      (params[:order] || []).each_with_index do |id, idx|
        FeatureRequest.where(id: id).update_all(order: idx)
      end
      head :ok
    end

    private

    def render_admin_feature_requests_flash_alert(message)
      render turbo_stream: turbo_stream.update(
        "admin_feature_requests_flash",
        helpers.tag.p(message, class: "rounded-lg border border-red-500/30 bg-red-500/10 px-4 py-2 text-sm text-red-400")
      ), status: :unprocessable_entity
    end

    def set_feature_request
      @feature_request = FeatureRequest.with_deleted.find(params[:id])
    end

    def admin_feature_request_params
      params.require(:feature_request).permit(:title, :description, :status, :admin_notes, :release_note_url, :order)
    end
  end
end
