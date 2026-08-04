class MfaSetupController < ApplicationController
  layout "application"

  before_action :authenticate_user!
  skip_before_action :validate_session
  skip_before_action :require_mfa_if_enabled
  skip_before_action :ensure_fully_authenticated
  skip_before_action :check_credentials_setup_required
  before_action :redirect_if_mfa_complete, only: [ :show, :verify ]
  before_action :check_profile_complete, only: [ :show, :verify ]

  # GET /mfa/setup
  def show
    @user = current_user

    begin
      @user.generate_otp_secret_if_needed unless @user.otp_secret.present?
    rescue => e
      Rails.logger.error("Failed to generate OTP secret: #{e.message}")
      flash.now[:alert] = t('controllers.mfa_setup.generate_failed')
    end

    begin
      @qr_code = @user.qr_code_svg
      @provisioning_uri = @user.otp_provisioning_uri
    rescue => e
      Rails.logger.error("Failed to generate QR code: #{e.message}")
      @qr_code = nil
      @provisioning_uri = nil
      flash.now[:alert] = t('controllers.mfa_setup.qr_failed')
    end

    # Restore selected plan ID ONLY if frozen
    if @user.selected_plan_id.blank? &&
       session[:selected_plan_id].present? &&
       session[:plan_id_frozen]
      @user.selected_plan_id = session[:selected_plan_id]
    end
  end


  # POST /mfa/setup/verify
  def verify
    @user = current_user
    code = params[:code]&.strip

    if code.blank?
      flash.now[:alert] = t('controllers.mfa_setup.enter_code')
      @qr_code = @user.qr_code_svg
      @provisioning_uri = @user.otp_provisioning_uri
      render :show, status: :unprocessable_entity
      return
    end

    if @user.verify_totp(code)
      @user.update!(
        mfa_enabled: true,
        mfa_verified: true
      )

      log_security_event(
        event: "auth.mfa_setup",
        status: "success",
        actor: @user
      )

      # Mark MFA as verified for this session (required for dashboard access)
      session[:mfa_verified] = true
      session[:mfa_verified_at] = Time.current.to_i

      # Ensure subscription exists (trial or free plan)
      if @user.trial_active?
        trial_sub = @user.current_subscription
        days_remaining = ((trial_sub.trial_ends_at - Time.current) / 1.day).ceil
        flash[:notice] = t('controllers.mfa_setup.trial_active', days: days_remaining)
      elsif @user.subscribed?
        flash[:notice] = t('controllers.mfa_setup.subscription_active')
      else
        # Ensure free plan exists (callback should have created it, but double-check)
        @user.ensure_free_plan_subscription unless @user.subscriptions.current.exists?
        flash[:notice] = t('controllers.mfa_setup.free_plan_welcome')
      end

      # Cleanup session (trial already created at signup)
      session.delete(:selected_plan_id)
      session.delete(:plan_id_frozen)

      if session[:post_signup_paid_plan_id].present?
        redirect_to signup_plan_choice_path
      elsif session[:pending_guild_invite_token].present?
        redirect_to join_complete_path
      else
        redirect_to dashboard_path
      end
    else
      log_security_event(
        event: "auth.mfa_setup",
        status: "failure",
        actor: @user
      )
      flash.now[:alert] = t('controllers.mfa_setup.invalid_code')
      @qr_code = @user.qr_code_svg
      @provisioning_uri = @user.otp_provisioning_uri
      render :show, status: :unprocessable_entity
    end
  end

  private

  def redirect_if_mfa_complete
    # Only redirect if MFA is already verified (not for Discord users setting up MFA as backup)
    redirect_to dashboard_path if current_user.mfa_verified?
  end

  def check_profile_complete
    # Reload user to ensure we have fresh data
    user = current_user
    user.reload if user.persisted?
    
    # Check if profile is complete before allowing MFA setup
    unless user.email.present? && user.username.present? && user.encrypted_password.present? && !user.email.include?("@discord.guildsync.local")
      redirect_to complete_profile_path, alert: t('controllers.mfa_setup.profile_incomplete')
      return
    end
  end

  def profile_complete?(user)
    user.email.present? &&
    user.username.present? &&
    user.encrypted_password.present? &&
    !user.email.include?("@discord.guildsync.local")
  end
end
