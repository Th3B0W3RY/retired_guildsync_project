# frozen_string_literal: true

class AccountDeletionsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_feature_enabled
  before_action :ensure_eligible, only: [ :send_code ]

  def send_code
    request_record = current_user.account_deletion_request || current_user.build_account_deletion_request

    unless request_record.resend_available?
      flash[:alert] = t("account_deletion.flash.resend_cooldown", seconds: request_record.resend_available_in)
      return redirect_to(account_settings_path)
    end

    raw = request_record.issue_code!(ip: request.remote_ip)
    AccountMailer.deletion_code(current_user.id, raw).deliver_now

    SecurityAuditLogger.log(
      event: "account_deletion_code_sent",
      status: "success",
      actor: current_user,
      subject: current_user,
      request: request
    )

    flash[:notice] = t("account_deletion.flash.code_sent")
    redirect_to account_settings_path
  end

  def confirm
    request_record = current_user.account_deletion_request
    if request_record.blank?
      flash[:alert] = t("account_deletion.flash.request_missing")
      return redirect_to(account_settings_path)
    end

    eligibility = AccountDeletion::EligibilityChecker.new(current_user).call
    unless eligibility.allowed?
      flash[:alert] = t("account_deletion.flash.blocked.#{eligibility.reason}", default: t("account_deletion.flash.blocked.generic"))
      return redirect_to(account_settings_path)
    end

    outcome = request_record.verify_submitted_code(params[:code])

    case outcome
    when :locked
      flash[:alert] = t("account_deletion.flash.too_many_attempts")
    when :expired
      flash[:alert] = t("account_deletion.flash.code_expired")
    when :invalid
      flash[:alert] = t("account_deletion.flash.code_invalid")
    when :ok
      return finalize_deletion!
    end

    redirect_to account_settings_path
  end

  private

  def ensure_feature_enabled
    return if AccountDeletion.feature_enabled?

    head :not_found
  end

  def ensure_eligible
    result = AccountDeletion::EligibilityChecker.new(current_user).call
    return if result.allowed?

    flash[:alert] = t("account_deletion.flash.blocked.#{result.reason}", default: t("account_deletion.flash.blocked.generic"))
    redirect_to account_settings_path
  end

  def finalize_deletion!
    user_id = current_user.id

    current_user.update_columns(
      archived: true,
      account_closed_at: Time.current,
      account_deletion_started_at: Time.current,
      updated_at: Time.current
    )

    sign_out(:user)
    reset_session

    SecurityAuditLogger.log(
      event: "account_deletion_confirmed",
      status: "success",
      actor: nil,
      subject: nil,
      request: request,
      metadata: { deleted_user_id: user_id }
    )

    AccountDeletionJob.perform_async(user_id)

    flash[:notice] = t("account_deletion.flash.completed")
    redirect_to root_path
  end
end
