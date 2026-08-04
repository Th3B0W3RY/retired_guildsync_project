# frozen_string_literal: true

module Admin
  class FeatureAbusersController < BaseController
    PER_PAGE = 30
    FEATURE_ABUSERS_RESULTS_FRAME = "admin_feature_abusers_results"

    def index
      load_feature_abusers_index
      if request.headers["Turbo-Frame"] == FEATURE_ABUSERS_RESULTS_FRAME
        render "feature_abusers_results_frame", layout: false
      end
    end

    def lock
      @user = User.find(params[:user_id])
      @user.update_columns(locked_at: Time.current) if @user.locked_at.nil?

      warning = UserComplianceWarning.find_or_initialize_by(
        user_id: @user.id,
        warning_type: UserComplianceWarning::WARNING_TYPE_IP_CONFLICT
      )
      warning.assign_attributes(
        active: true,
        message: I18n.t("compliance.ip_conflict.warning_message"),
        locked_by_policy: false,
        last_detected_at: Time.current,
        resolved_at: nil
      )
      warning.save!

      log_admin_action(action: "feature_abuser_lock", record: @user)
      @user.reload
      @user.user_compliance_warnings.reload
      @feature_abusers_notice = I18n.t("admin.feature_abusers.flash.locked")
      respond_to do |format|
        format.html { redirect_to admin_feature_abusers_path, notice: @feature_abusers_notice }
        format.turbo_stream { render :lock }
      end
    end

    def unlock
      @user = User.find(params[:user_id])
      @user.update_columns(locked_at: nil) if @user.respond_to?(:locked_at)

      UserComplianceWarning.where(
        user_id: @user.id,
        warning_type: UserComplianceWarning::WARNING_TYPE_IP_CONFLICT
      ).find_each do |w|
        w.update_columns(active: false, resolved_at: Time.current, locked_by_policy: false)
      end

      log_admin_action(action: "feature_abuser_unlock", record: @user)
      @user.reload
      @user.user_compliance_warnings.reload
      @feature_abusers_notice = I18n.t("admin.feature_abusers.flash.unlocked")
      respond_to do |format|
        format.html { redirect_to admin_feature_abusers_path, notice: @feature_abusers_notice }
        format.turbo_stream { render :unlock }
      end
    end

    private

    def load_feature_abusers_index
      @filter = params[:filter].presence_in(%w[all locked warned]) || "all"
      @q = params[:q].to_s.strip

      wt = UserComplianceWarning::WARNING_TYPE_IP_CONFLICT
      scope = User.where(
        "users.id IN (SELECT user_id FROM user_compliance_warnings WHERE active = TRUE AND warning_type = ?) OR users.locked_at IS NOT NULL",
        wt
      )

      if @filter == "locked"
        scope = scope.where.not(locked_at: nil)
      elsif @filter == "warned"
        scope = scope.where(locked_at: nil).where(
          "users.id IN (SELECT user_id FROM user_compliance_warnings WHERE active = TRUE AND warning_type = ?)",
          wt
        )
      end

      if @q.present?
        if @q.match?(/\A\d+\z/)
          scope = scope.where(id: @q.to_i)
        else
          safe = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
          scope = scope.where("users.email ILIKE :q OR users.username ILIKE :q", q: safe)
        end
      end

      scope = scope.order("users.locked_at DESC NULLS LAST, users.id DESC")
      @total = scope.count
      page = [ params[:page].to_i, 1 ].max
      @users = scope.includes(:user_compliance_warnings).offset((page - 1) * PER_PAGE).limit(PER_PAGE)
      @current_page = page
      @total_pages = (@total.to_f / PER_PAGE).ceil
    end
  end
end
