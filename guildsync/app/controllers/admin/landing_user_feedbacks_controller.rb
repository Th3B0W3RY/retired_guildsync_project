# frozen_string_literal: true

module Admin
  class LandingUserFeedbacksController < BaseController
    include Admin::TurboDashboardFrame

    before_action :set_landing_user_feedback, only: [ :edit, :update, :destroy ]
    before_action :ensure_below_entry_limit!, only: [ :new ]

    def index
      @carousel_interval_seconds =
        (SiteSetting.landing_feedback_carousel_interval_ms / 1000.0).round.clamp(2, 60)
      @recovery_status = params[:recovery_status].presence_in(%w[active deleted all]) || "active"
      @landing_user_feedbacks =
        case @recovery_status
        when "deleted" then LandingUserFeedback.with_deleted.deleted.ordered
        when "all" then LandingUserFeedback.with_deleted.ordered
        else LandingUserFeedback.ordered
        end
      return if respond_with_dashboard_frame(:index_frame)
    end

    def new
      @landing_user_feedback = LandingUserFeedback.new(visible: true, position: next_position)
      return if respond_with_dashboard_frame(:new_frame)
    end

    def create
      @landing_user_feedback = LandingUserFeedback.new(admin_params.merge(position: next_position))
      if @landing_user_feedback.save
        log_admin_action(action: "create_landing_user_feedback", changes_data: { id: @landing_user_feedback.id })
        redirect_to admin_landing_user_feedbacks_path, notice: t("admin.landing_user_feedbacks.created")
      else
        flash.now[:alert] = @landing_user_feedback.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      return if respond_with_dashboard_frame(:edit_frame)
    end

    def update
      if @landing_user_feedback.update(admin_params)
        log_admin_action(action: "update_landing_user_feedback", changes_data: { id: @landing_user_feedback.id })
        redirect_to admin_landing_user_feedbacks_path, notice: t("admin.landing_user_feedbacks.updated")
      else
        flash.now[:alert] = @landing_user_feedback.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      id = @landing_user_feedback.id
      @landing_user_feedback.soft_delete!
      log_admin_action(action: "destroy_landing_user_feedback", changes_data: { id: id, soft_delete: true })
      redirect_to admin_landing_user_feedbacks_path, notice: t("admin.landing_user_feedbacks.destroyed")
    end

    def reorder
      ids = Array(params[:order]).map(&:to_i).reject(&:zero?)
      unless complete_reorder_payload?(ids)
        head :unprocessable_entity
        return
      end

      LandingUserFeedback.transaction do
        ids.each_with_index do |id, idx|
          LandingUserFeedback.with_deleted.where(id: id).update_all(position: idx)
        end
      end
      head :ok
    end

    def update_carousel_settings
      seconds = params[:carousel_interval_seconds].to_i
      seconds = 2 if seconds < 2
      seconds = 60 if seconds > 60
      ms = seconds * 1000

      SiteSetting.set("landing_feedback_carousel_interval_ms", ms.to_s)
      log_admin_action(action: "update_landing_feedback_carousel", changes_data: { interval_ms: ms })
      redirect_to admin_landing_user_feedbacks_path,
                  notice: t("admin.landing_user_feedbacks.carousel_settings.updated")
    end

    private

    def set_landing_user_feedback
      @landing_user_feedback = LandingUserFeedback.with_deleted.find(params[:id])
    end

    def admin_params
      params.require(:landing_user_feedback).permit(:visible, :body)
    end

    def next_position
      (LandingUserFeedback.with_deleted.maximum(:position) || -1) + 1
    end

    def complete_reorder_payload?(ids)
      expected_ids = LandingUserFeedback.active.order(:id).pluck(:id)
      ids.uniq.length == expected_ids.length && ids.sort == expected_ids
    end

    def ensure_below_entry_limit!
      return if LandingUserFeedback.active.count < LandingUserFeedback::MAX_ENTRIES

      redirect_to admin_landing_user_feedbacks_path,
                  alert: t("admin.landing_user_feedbacks.at_limit", max: LandingUserFeedback::MAX_ENTRIES)
    end
  end
end
