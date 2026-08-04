# frozen_string_literal: true

class BackupCodesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :verify ]
  skip_before_action :require_mfa_if_enabled, only: [ :verify ]
  skip_before_action :ensure_fully_authenticated, only: [ :verify ]

  def generate
    regenerate
  end

  def regenerate
    unless current_user.verified_real_email?
      redirect_to account_settings_path, alert: I18n.t("settings.account.backup_codes.verify_email_first")
      return
    end

    unless current_user.backup_code_regeneration_available?
      redirect_to account_settings_path,
                  alert: I18n.t(
                    "settings.account.backup_codes.cooldown_active",
                    date: I18n.l(current_user.backup_code_regeneration_available_at.to_date, format: :long)
                  )
      return
    end

    result = BackupCodeGenerator.generate_for_user(current_user)
    backup_code = result[:codes].first

    current_user.update_columns(
      backup_code_regenerated_at: Time.current,
      last_backup_generation_at: Time.current,
      last_backup_generation_ip: request.remote_ip
    )

    log_security_event(
      event: "backup_codes.regenerated",
      status: "success",
      metadata: { delivery: "email" }
    )

    AccountMailer.backup_code_regenerated(current_user, backup_code).deliver_later
    redirect_to account_settings_path, notice: I18n.t("settings.account.backup_codes.regenerated_notice")
  end

  def verify
    user = User.find_by(email: params[:email].to_s.downcase.strip)
    invalid_message = I18n.t("backup_codes.verify.invalid_email_or_code", default: "Invalid email or backup code.")
    unless user
      flash[:alert] = invalid_message
      redirect_to new_password_path and return
    end

    if BackupCode.valid_for_user?(user, params[:backup_code], request: request)
      session[:recovery_user_id] = user.id
      session[:recovery_method] = "backup_code"
      session[:recovery_time] = Time.current.to_i
      log_security_event(
        event: "backup_codes.verified",
        status: "success",
        actor: user,
        metadata: { recovery: true }
      )
      redirect_to recover_account_path, notice: I18n.t("backup_codes.verify.success", default: "Backup code accepted. Set a new password below.")
    else
      flash[:alert] = invalid_message
      redirect_to new_password_path
    end
  end
end
