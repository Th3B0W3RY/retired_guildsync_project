# frozen_string_literal: true

module Admin
  class UserComplianceController < BaseController
    LOGIN_HISTORY_MAIN_FRAME = "admin_user_compliance_login_history_main"

    def force_logout
      user = User.find(params[:user_id])
      # Clear all sessions for the user
      LoginHistory.where(user: user, logout_at: nil).update_all(logout_at: Time.current)
      log_admin_action(action: "force_logout", record: user)
      @admin_compliance_notice = I18n.t("admin.user_compliance.flash.force_logout")
      respond_to do |format|
        format.html { redirect_to admin_user_path(user), notice: @admin_compliance_notice }
        format.turbo_stream { render :compliance_notice_flash }
      end
    end

    def reset_mfa
      user = User.find(params[:user_id])
      user.update_columns(
        otp_secret: nil,
        mfa_enabled: false,
        mfa_verified: false
      )
      log_admin_action(action: "reset_mfa", record: user)
      @admin_compliance_notice = I18n.t("admin.user_compliance.flash.reset_mfa")
      respond_to do |format|
        format.html { redirect_to admin_user_path(user), notice: @admin_compliance_notice }
        format.turbo_stream { render :compliance_notice_flash }
      end
    end

    def reset_email
      user = User.find(params[:user_id])
      old_email = user.email
      new_email = params[:new_email].to_s.strip
      user.update_columns(email: new_email)
      log_admin_action(
        action: "reset_email",
        record: user,
        changes_data: { old_email: old_email, new_email: new_email }
      )
      @user = user.reload
      @admin_compliance_notice = I18n.t("admin.user_compliance.flash.reset_email")
      @turbo_refresh_user_email = true
      respond_to do |format|
        format.html { redirect_to admin_user_path(user), notice: @admin_compliance_notice }
        format.turbo_stream { render :compliance_refresh }
      end
    end

    def disable_account
      user = User.find(params[:user_id])
      user.update_columns(locked_at: Time.current)
      log_admin_action(action: "disable_account", record: user)
      @user = user.reload
      @admin_compliance_notice = I18n.t("admin.user_compliance.flash.account_disabled")
      @turbo_refresh_user_email = false
      respond_to do |format|
        format.html { redirect_to admin_user_path(user), notice: @admin_compliance_notice }
        format.turbo_stream { render :compliance_refresh }
      end
    end

    def enable_account
      user = User.find(params[:user_id])
      user.update_columns(locked_at: nil)
      log_admin_action(action: "enable_account", record: user)
      @user = user.reload
      @admin_compliance_notice = I18n.t("admin.user_compliance.flash.account_enabled")
      @turbo_refresh_user_email = false
      respond_to do |format|
        format.html { redirect_to admin_user_path(user), notice: @admin_compliance_notice }
        format.turbo_stream { render :compliance_refresh }
      end
    end

    def login_history
      load_login_history_show
      return render("login_history_frame", layout: false) if request.headers["Turbo-Frame"] == LOGIN_HISTORY_MAIN_FRAME
    end

    private

    def load_login_history_show
      @user = User.find(params[:user_id])
      @login_histories = @user.login_histories.recent.limit(50)
    end
  end
end
