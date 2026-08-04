class SessionsController < Devise::SessionsController
  include MfaVerification

  layout "application"

  before_action :redirect_if_authenticated, only: [ :new, :create ]
  # User may sign out while MFA setup/verification is still pending; do not trap them in ensure_fully_authenticated.
  skip_before_action :ensure_fully_authenticated, only: [ :destroy ]

  def new
    # Auto-redirect returning Discord users to silent-login if a valid
    # UserDiscordConnection with a refresh token exists. Validates server-side
    # to avoid redirect loops when the cookie outlives the DB record (e.g. DB wipe).
    # Skipped when: cookie absent, user explicitly signed out (session cookie),
    # force_load param is present (post-sign-out page reload),
    # or email_login=1 (main nav "Sign in" — always show password form first; avoids
    # intermittent /login <-> /auth/discord loops when silent OAuth/session persistence fails).
    if cookies.signed[:discord_uid].present? &&
        !cookies.signed[:discord_signed_out].present? &&
        params[:force_load].blank? &&
        params[:email_login].blank?
      # Fastest path: refresh + sign in inline (no extra hop to /auth/discord, no
      # discord.com round-trip) when the stored connection is usable.
      silent = Discord::CookieSilentSignIn.call(cookies.signed[:discord_uid])
      if silent.signed_in?
        Discord::OAuthPrimarySession.apply!(self, silent.user)
        redirect_to(stored_location_for(:user) || dashboard_path)
        return
      else
        # Dead identity for silent login: drop the stale uid but keep discord_seen_before
        # so a click on "Sign in with Discord" still gets a silent authorize (prompt=none).
        cookies.delete(:discord_uid)
      end
    end

    if params[:signed_out].present? && params[:force_load].blank? && cookies.signed[:signed_out_toast].present?
      flash.now[:notice] = I18n.t("flash.signed_out")
      cookies.delete(:signed_out_toast)
    end
    super
  end

  def create
    authenticated_user = nil

    # Let Devise handle authentication, but set flag after successful login
    super do |resource|
      authenticated_user = resource
      # This block runs only if authentication was successful
      flash[:notice] = I18n.t("flash.signed_in")
      # Mark that user just logged in - required for MFA verification
      session[:just_logged_in] = true

      # Store user ID in session as backup (in case Warden session isn't preserved)
      # This ensures we can load the user even if Warden's session data is lost
      session[:user_id] = resource.id

      # Never reuse MFA session flags from a previous browser session or another account.
      # Stale :mfa_verified let users hit member chrome / dashboard before entering TOTP.
      if resource.auth_method == "mfa" && resource.mfa_enabled?
        test_autoverify = Rails.env.test? && User.skip_mfa_verification?(resource.id)
        unless test_autoverify
          session.delete(:mfa_verified)
          session.delete(:mfa_verified_at)
        end
      end

      # In test environment, automatically set MFA verification for users who:
      # 1. Have MFA enabled/verified
      # 2. Have skip_mfa_verification flag set (opt-in for integration tests)
      # This bypasses the manual MFA verification step for test users (not testing MFA specifically)
      # RSpec tests that create users via factories won't have this flag, so they'll test MFA flow normally
      if Rails.env.test? &&
         resource.auth_method == "mfa" &&
         resource.mfa_enabled? &&
         resource.mfa_verified? &&
         User.skip_mfa_verification?(resource.id)
        session[:mfa_verified] = true
        session[:mfa_verified_at] = Time.current.to_i
      end

      # Ensure session is saved and persisted before redirect
      # This is critical for the redirect to MFA verification to work
      if session.respond_to?(:save)
        session.save
      elsif session.respond_to?(:commit)
        session.commit
      end

      # Force Warden to persist the session by accessing it
      # This ensures the user is properly signed in before redirect
      warden.set_user(resource, scope: :user) unless warden.user(scope: :user) == resource

      begin
        LoginHistory.log_login(user: resource, ip_address: request.remote_ip, user_agent: request.user_agent)
      rescue => e
        Rails.logger.warn("LoginHistory.log_login failed for user #{resource.id}: #{e.class} #{e.message}")
      end
      audit_security_event(
        event: "auth.login",
        status: "success",
        actor: resource,
        metadata: { provider: "password" }
      )
    end

    if authenticated_user.nil?
      audit_security_event(
        event: "auth.login",
        status: "failure",
        actor: nil,
        metadata: { provider: "password" }
      )
    end
  rescue StandardError => e
    audit_security_event(
      event: "auth.login",
      status: "error",
      actor: nil,
      metadata: { provider: "password", error_class: e.class.name }
    )
    Rails.logger.error "Login failure: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    flash.now[:alert] = I18n.t(
      "devise.failure.invalid",
      authentication_keys: User.human_attribute_name(:email),
      default: "Login failed."
    )
    render :new, status: :unprocessable_entity
  end

  def destroy
    user = current_user

    # Logout only clears Rails session/cookies. Do NOT clear Discord cookies or revoke tokens;
    # only the explicit "Disconnect Discord" action revokes and removes Discord linkage.

    # Clear all session keys before reset
    session.delete(:mfa_verified)
    session.delete(:mfa_verified_at)
    session.delete(:selected_plan_id)
    session.delete(:plan_id_frozen)
    session.delete(:just_logged_in)

    # Reset entire session to guarantee complete logout
    reset_session

    sign_out(:user)

    if user
      begin
        login_history = LoginHistory.for_user(user).active_sessions.recent.first
        login_history&.log_logout!
      rescue => e
        Rails.logger.warn("LoginHistory.log_logout failed for user #{user.id}: #{e.class} #{e.message}")
      end
      audit_security_event(
        event: "auth.logout",
        status: "success",
        actor: user,
        metadata: { provider: user.auth_method.to_s }
      )
    end

    # Mint short-lived proof of real sign-out so direct /login?signed_out=1
    # cannot spoof the success toast.
    cookies.signed[:signed_out_toast] = {
      value: "1",
      expires: 1.minute.from_now,
      httponly: true,
      same_site: :lax
    }

    # Signal that the user explicitly signed out. This cookie persists for the
    # lifetime of the browser session (no `expires` = session cookie). Silent
    # Discord re-login is suppressed until the user closes and reopens the browser,
    # at which point the session cookie is cleared and silent login resumes for
    # returning visitors who still have a valid discord_uid cookie.
    cookies.signed[:discord_signed_out] = {
      value: "1",
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }

    # Flash won't survive the force_load double-redirect; use signed_out param
    # + signed cookie to show toast only after an actual logout.
    redirect_to after_sign_out_path_for(:user)
  end

  protected

  def after_sign_in_path_for(resource)
    # If user has a pending one-time invite link, send them to complete it after MFA
    if session[:pending_guild_invite_token].present?
      return mfa_setup_path if resource.auth_method == "mfa" && !resource.mfa_enabled?
      return mfa_verification_path(return_to: join_complete_path) if resource.auth_method == "mfa" && resource.mfa_enabled?
      return join_complete_path if resource.oauth_primary_auth? && session[:mfa_verified]
      return mfa_verification_path(return_to: join_complete_path)
    end
    # If user uses Discord auth and is already verified via Discord, go to dashboard
    if resource.oauth_primary_auth? && session[:mfa_verified]
      dashboard_path
    # If user has MFA auth method but MFA is not enabled, force MFA setup
    elsif resource.auth_method == "mfa" && !resource.mfa_enabled?
      mfa_setup_path
    elsif !resource.mfa_enabled? || !resource.mfa_verified?
      mfa_setup_path
    else
      # Universal redirect to dashboard (works for both owners and members)
      mfa_verification_path(return_to: dashboard_path)
    end
  end

  def after_sign_out_path_for(_resource_or_scope)
    # force_load ensures a full page load so "Sign in with Discord" works.
    # signed_out param survives the force_load double-redirect so the toast is shown.
    path = login_path(force_load: 1, signed_out: 1)
    Rails.logger.info "[Sessions] after_sign_out_path_for => #{path}"
    path
  end

  private

  def audit_security_event(event:, status:, actor:, metadata: {})
    SecurityAuditLogger.log(
      event: event,
      status: status,
      actor: actor,
      request: request,
      metadata: metadata
    )
  end

  def redirect_if_authenticated
    if user_signed_in? && current_user.present?
      flash.clear
      if mfa_verified_for_session?
        redirect_to dashboard_path if request.get? && !request.xhr?
      elsif request.get? && !request.xhr?
        # Do not reset_session — user may be mid MFA step-up; send them back into post-login flow.
        redirect_to after_sign_in_path_for(current_user)
      end
    elsif user_signed_in? && current_user.nil?
      reset_session
      flash.clear
    end
  end
end
