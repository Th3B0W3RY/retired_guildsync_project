# frozen_string_literal: true

class RecoveriesController < ApplicationController
  layout "application"
  skip_before_action :authenticate_user!
  skip_before_action :require_mfa_if_enabled
  skip_before_action :ensure_fully_authenticated

  before_action :verify_recovery_session, only: [:edit, :update]

  def edit
    @user = User.find(session[:recovery_user_id])
    @recovery_method = session[:recovery_method]
  end

  def update
    @user = User.find(session[:recovery_user_id])

    if @user.update(password_reset_params)
      if params[:reset_mfa] == "1"
        @user.update_columns(
          otp_secret: nil,
          mfa_enabled: false,
          mfa_verified: false
        )
      end

      log_security_event(
        event: "account_recovery.completed",
        status: "success",
        actor: @user,
        metadata: {
          password_reset: true,
          mfa_reset: params[:reset_mfa] == "1"
        }
      )

      session.delete(:recovery_user_id)
      session.delete(:recovery_method)
      session.delete(:recovery_time)

      redirect_to login_path, notice: I18n.t("recoveries.update.success", default: "Your account has been recovered. Please sign in with your new password.")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def verify_recovery_session
    unless session[:recovery_user_id].present? &&
           session[:recovery_method] == "backup_code" &&
           session[:recovery_time].present? &&
           session[:recovery_time] > 15.minutes.ago.to_i
      redirect_to new_password_path, alert: I18n.t("recoveries.expired", default: "Recovery session expired. Please start over.")
    end
  end

  def password_reset_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
