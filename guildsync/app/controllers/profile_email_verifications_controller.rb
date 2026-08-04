# frozen_string_literal: true

# Confirms a new email for an existing account (link from SignupMailer#verify_profile_email).
class ProfileEmailVerificationsController < ApplicationController
  skip_before_action :validate_session, only: [ :show ]
  skip_before_action :authenticate_user!, only: [ :show ]
  skip_before_action :check_credentials_setup_required, only: [ :show ]
  skip_before_action :require_mfa_if_enabled, only: [ :show ]
  skip_before_action :ensure_fully_authenticated, only: [ :show ]

  def show
    verification = SignupEmailVerification.find_verifiable_token(params[:token].to_s)
    unless verification&.user_id.present?
      redirect_to profile_settings_path, alert: I18n.t("settings.profile.email_verification.invalid_link")
      return
    end

    user = User.find_by(id: verification.user_id)
    unless user
      redirect_to login_path, alert: I18n.t("settings.profile.email_verification.invalid_link")
      return
    end

    new_email = verification.email
    if User.where.not(id: user.id).exists?(email: new_email)
      redirect_to profile_settings_path, alert: I18n.t("settings.profile.email.taken")
      return
    end

    ActiveRecord::Base.transaction do
      user.skip_reconfirmation! if user.respond_to?(:skip_reconfirmation!)
      user.update!(email: new_email, signup_email_verified_at: Time.current)
      verification.verify!
    end

    log_security_event(
      event: "profile.email_verified",
      status: "success",
      actor: user,
      metadata: { purpose: "profile_settings" }
    )

    sign_in(user, event: :authentication)
    redirect_to profile_settings_path, notice: I18n.t("settings.profile.email_verification.success_notice")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to profile_settings_path,
                alert: e.record.errors.full_messages.to_sentence.presence ||
                  I18n.t("settings.profile.email_verification.update_failed")
  end
end
