class MfaVerificationController < ApplicationController
  layout "application"

  skip_before_action :validate_session
  skip_before_action :authenticate_user!
  skip_before_action :require_mfa_if_enabled
  skip_before_action :ensure_fully_authenticated
  before_action :ensure_user_authenticated
  before_action :require_mfa_verification

  # GET /mfa/verify - Show MFA verification form
  def show
    # Store the intended destination if provided (e.g. join_complete for one-time invite links)
    session[:mfa_return_to] = params[:return_to] if params[:return_to].present?
  end

  # POST /mfa/verify - Verify TOTP code
  def verify
    code = params[:code]&.strip

    if code.blank?
      flash.now[:alert] = t('controllers.mfa_verification.enter_code')
      render :show, status: :unprocessable_entity
      return
    end

    if current_user.verify_totp(code)
      # Mark MFA as verified for this session
      session[:mfa_verified] = true
      session[:mfa_verified_at] = Time.current.to_i

      log_security_event(
        event: "auth.mfa_verify",
        status: "success",
        actor: current_user
      )

      # Clear the just_logged_in flag since MFA is now verified
      session.delete(:just_logged_in)

      # Redirect to intended destination or dashboard
      redirect_to session[:mfa_return_to] || dashboard_path, notice: t('controllers.mfa_verification.success')
    else
      log_security_event(
        event: "auth.mfa_verify",
        status: "failure",
        actor: current_user
      )
      flash.now[:alert] = t('controllers.mfa_verification.invalid_code')
      render :show, status: :unprocessable_entity
    end
  end

  private

  def ensure_user_authenticated
    # Manually check if user is authenticated via Warden (Devise's authentication system)
    # This is needed because authenticate_user! redirects, but we need to handle it ourselves
    
    # First, try to get user from Warden (Devise's standard way)
    warden_user = warden.user(scope: :user, run_callbacks: false)
    
    if warden_user
      # User is authenticated via Warden - ensure current_user is set
      @current_user = warden_user
      # Ensure session backup is set
      session[:user_id] = warden_user.id
      return true
    end
    
    # If Warden doesn't have the user, try user_signed_in? as fallback
    if user_signed_in? && current_user.present?
      # Ensure session backup is set
      session[:user_id] = current_user.id
      return true
    end
    
    # If both fail, try loading from session[:user_id] (backup method)
    # This handles the case where Warden session isn't preserved but we have session[:user_id]
    if session[:user_id].present? && session[:just_logged_in]
      user = User.find_by(id: session[:user_id])
      if user
        # Manually sign in the user via Warden to restore the session
        sign_in(user)
        @current_user = user
        # Ensure Warden persists the session
        warden.set_user(user, scope: :user)
        return true
      else
        Rails.logger.warn("MfaVerificationController: Invalid user_id in session: #{session[:user_id]}")
      end
    end
    
    # No authenticated user found
    Rails.logger.warn("MfaVerificationController: Authentication failed - user not found in session")
    Rails.logger.warn("  session[:user_id]: #{session[:user_id].inspect}")
    Rails.logger.warn("  session[:just_logged_in]: #{session[:just_logged_in].inspect}")
    Rails.logger.warn("  warden_user: #{warden_user.inspect}")
    Rails.logger.warn("  user_signed_in?: #{user_signed_in?}")
    reset_session
    redirect_to login_path, alert: t('controllers.mfa_verification.sign_in_first')
    return false
  end

  def require_mfa_verification
    # Verify user is actually signed in with a valid user
    unless user_signed_in? && current_user.present?
      # Clear any stale session data
      reset_session
      redirect_to login_path, alert: t('controllers.mfa_verification.sign_in_first')
      return
    end

    # If MFA is not enabled, redirect to setup
    unless current_user.mfa_enabled?
      # Clear the just_logged_in flag since we're redirecting to setup
      session.delete(:just_logged_in)
      redirect_to mfa_setup_path, alert: t('controllers.mfa_verification.setup_first')
      return
    end

    # If already verified in this session (within last 30 minutes), redirect to dashboard
    if session[:mfa_verified] && session[:mfa_verified_at]
      verified_at = Time.at(session[:mfa_verified_at])
      if verified_at > 30.minutes.ago
        # Clear the just_logged_in flag since verification is already done
        session.delete(:just_logged_in)
        redirect_to session[:mfa_return_to] || dashboard_path, alert: t('controllers.mfa_verification.already_verified')
        nil
      else
        # Session expired - allow re-verification (this is the fix for the lockout issue)
        # Clear the expired verification flags
        session.delete(:mfa_verified)
        session.delete(:mfa_verified_at)
        # Allow them to proceed with re-verification
      end
    end

    # Allow verification if:
    # 1. User just logged in (session[:just_logged_in] == true), OR
    # 2. MFA session expired and user needs to re-verify (session[:mfa_verified] is nil/false)
    # This fixes the lockout issue where users couldn't re-verify after 30 minutes
  end
end
