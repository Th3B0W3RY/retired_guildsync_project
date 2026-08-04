# frozen_string_literal: true

class AccountCreationController < ApplicationController
  include SignupCaptchaVerifiable

  skip_before_action :validate_session
  skip_before_action :authenticate_user!
  skip_before_action :check_credentials_setup_required
  skip_before_action :require_mfa_if_enabled
  skip_before_action :ensure_fully_authenticated

  def show
    @email = params[:email].to_s
  end

  def create
    return render_email_form unless signup_turnstile_result == :ok

    email = SignupEmailVerification.normalize_email(params[:email])
    unless valid_signup_email?(email)
      flash.now[:alert] = t("account_creation.invalid_email")
      @email = email
      render :show, status: :unprocessable_entity
      return
    end

    if User.where(email: email).where.not(registration_completed_at: nil).exists?
      flash.now[:alert] = t("account_creation.email_taken")
      @email = email
      render :show, status: :unprocessable_entity
      return
    end

    verification = find_or_initialize_verification(email)
    send_verification_email(verification)
    session[:signup_verification_id] = verification.id
    redirect_to create_account_sent_path, notice: t("account_creation.sent_notice")
  end

  def sent
    @verification = current_verification
    redirect_to create_account_path, alert: t("account_creation.start_over") unless @verification
  end

  def resend
    @verification = current_verification
    unless @verification
      redirect_to create_account_path, alert: t("account_creation.start_over")
      return
    end

    return redirect_to(create_account_sent_path, alert: t("account_creation.already_verified")) if @verification.verified_at.present?
    return render_resend_cooldown unless @verification.resend_available?
    return redirect_to(create_account_sent_path, alert: t("registrations.errors.captcha_invalid")) unless signup_turnstile_result == :ok

    send_verification_email(@verification)
    redirect_to create_account_sent_path, notice: t("account_creation.resent_notice")
  end

  def verify
    verification = SignupEmailVerification.find_verifiable_token(params[:token])
    unless verification
      redirect_to create_account_path, alert: t("account_creation.invalid_or_expired")
      return
    end

    if verification.user_id.present?
      redirect_to create_account_path, alert: t("account_creation.invalid_or_expired")
      return
    end

    user = nil
    backup_code = nil
    ActiveRecord::Base.transaction do
      user = AccountCreation::ProvisionalUserBuilder.call(email: verification.email, ip_address: request.remote_ip)
      backup_code = BackupCodeGenerator.generate_for_user(user)[:codes].first
      verification.verify!
    end
    session[:signup_verification_id] = verification.id
    session[:signup_user_id] = user.id
    session[:signup_backup_code] = backup_code
    redirect_to create_account_backup_code_path, notice: t("account_creation.verified_notice")
  rescue ActiveRecord::RecordInvalid => e
    AccountCreation::SignupSession.clear!(session)
    if e.record.is_a?(User)
      redirect_to create_account_path, alert: t("account_creation.email_taken")
    else
      Rails.logger.error("[AccountCreation] email verification failed: #{e.class}: #{e.message}")
      redirect_to create_account_path, alert: t("account_creation.start_over")
    end
  rescue StandardError => e
    Rails.logger.error("[AccountCreation] email verification failed: #{e.class}: #{e.message}")
    AccountCreation::SignupSession.clear!(session)
    redirect_to create_account_path, alert: t("account_creation.start_over")
  end

  def backup_code
    @user = signup_user
    return redirect_to(create_account_path, alert: t("account_creation.start_over")) unless @user

    generate_signup_backup_code(@user) if session[:signup_backup_code].blank?
    @backup_code = session[:signup_backup_code]
  end

  def confirm_backup_code
    user = signup_user
    return redirect_to(create_account_path, alert: t("account_creation.start_over")) unless user

    unless ActiveModel::Type::Boolean.new.cast(params[:backup_code_saved])
      @user = user
      @backup_code = session[:signup_backup_code]
      flash.now[:alert] = t("account_creation.backup_code.confirm_required")
      render :backup_code, status: :unprocessable_entity
      return
    end

    user.update!(backup_code_acknowledged_at: Time.current)
    session[:signup_backup_confirmed] = true
    session.delete(:signup_backup_code)
    redirect_to create_account_choose_method_path
  end

  def choose_method
    return unless ensure_backup_confirmed # rubocop:disable Style/RedundantReturn -- halt after redirect inside guard
  end

  def standard
    return unless ensure_backup_confirmed

    @user = signup_user
  end

  def standard_create
    return unless ensure_backup_confirmed

    @user = signup_user
    unless @user.update(standard_account_params.merge(auth_method: :mfa, registration_completed_at: Time.current))
      render :standard, status: :unprocessable_entity
      return
    end

    finish_password_signup(@user)
  end

  def discord
    return unless ensure_backup_confirmed

    session[:signup_method] = "discord"
    redirect_to discord_login_path(signup: true)
  end

  def google
    return unless ensure_backup_confirmed

    session[:signup_method] = "google"
    redirect_to google_login_path(signup: true)
  end

  def microsoft
    return unless ensure_backup_confirmed

    session[:signup_method] = "microsoft"
    redirect_to microsoft_login_path(signup: true)
  end

  private

  def render_email_form
    @email = params[:email].to_s
    flash.now[:alert] = t("registrations.errors.captcha_invalid")
    render :show, status: :unprocessable_entity
  end

  def valid_signup_email?(email)
    email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def find_or_initialize_verification(email)
    SignupEmailVerification.unverified.where(user_id: nil).find_or_initialize_by(email: email)
  end

  def send_verification_email(verification)
    raw_token = verification.issue!(ip_address: request.remote_ip)
    SignupMailer.verify_email(verification, raw_token).deliver_later
  end

  def current_verification
    SignupEmailVerification.find_by(id: session[:signup_verification_id])
  end

  def signup_user
    User.find_by(id: session[:signup_user_id])
  end

  def generate_signup_backup_code(user)
    return if session[:signup_backup_code].present?

    result = BackupCodeGenerator.generate_for_user(user)
    session[:signup_backup_code] = result[:codes].first
  end

  def ensure_backup_confirmed
    if signup_user.blank?
      redirect_to create_account_path, alert: t("account_creation.start_over")
      return false
    end

    unless session[:signup_backup_confirmed] && signup_user.backup_code_acknowledged_at.present?
      redirect_to create_account_backup_code_path, alert: t("account_creation.backup_code.must_confirm")
      return false
    end

    true
  end

  def standard_account_params
    params.require(:user).permit(:username, :password, :password_confirmation)
  end

  def finish_password_signup(user)
    AccountCreation::SignupSession.clear!(session)
    sign_in(user, event: :authentication)
    session[:user_id] = user.id
    session[:just_logged_in] = true
    redirect_to mfa_setup_path, notice: t("account_creation.standard.created")
  end

  def render_resend_cooldown
    redirect_to create_account_sent_path,
                alert: t("account_creation.resend_cooldown", seconds: @verification.resend_available_in)
  end
end
