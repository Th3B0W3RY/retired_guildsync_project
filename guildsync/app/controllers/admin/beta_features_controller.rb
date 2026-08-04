# frozen_string_literal: true

module Admin
  class BetaFeaturesController < BaseController
    PER_PAGE = 30
    BETA_FEATURES_RESULTS_FRAME = "admin_beta_features_results"

    def index
      load_beta_features_index
      if request.headers["Turbo-Frame"] == BETA_FEATURES_RESULTS_FRAME
        render "beta_features_results_frame", layout: false
      end
    end

    def enable
      @user = User.find(params[:user_id])
      @user.update!(beta_features_enabled: true)
      log_admin_action(
        action: "beta_features_enable",
        record: @user,
        changes_data: { beta_features_enabled: true }
      )
      @beta_features_notice = I18n.t("admin.beta_features.enabled_notice")
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_beta_features_path, notice: @beta_features_notice }
        format.turbo_stream { render :enable }
      end
    end

    def disable
      @user = User.find(params[:user_id])
      @user.update!(beta_features_enabled: false)
      log_admin_action(
        action: "beta_features_disable",
        record: @user,
        changes_data: { beta_features_enabled: false }
      )
      @beta_features_notice = I18n.t("admin.beta_features.disabled_notice")
      respond_to do |format|
        format.html { redirect_back fallback_location: admin_beta_features_path, notice: @beta_features_notice }
        format.turbo_stream { render :disable }
      end
    end

    private

    def load_beta_features_index
      @q = params[:q].to_s.strip
      scope = User.all
      if @q.present?
        if @q.match?(/\A\d+\z/)
          scope = scope.where(id: @q.to_i)
        else
          safe = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
          scope = scope.where("users.email ILIKE :q OR users.username ILIKE :q", q: safe)
        end
      end
      scope = scope.order(id: :desc)
      @total = scope.count
      @current_page = [ params[:page].to_i, 1 ].max
      @total_pages = (@total.to_f / PER_PAGE).ceil
      @users = scope.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)
      @per_page = PER_PAGE
    end
  end
end
