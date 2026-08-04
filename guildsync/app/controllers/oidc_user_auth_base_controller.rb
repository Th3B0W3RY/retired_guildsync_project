# frozen_string_literal: true

# Shared OAuth2/OIDC flow for Gmail and Outlook account login and gated account creation.
# Subclasses define +oidc_service+, +oauth_session_prefix+, +user_uid_column+, +auth_method_key+,
# +verify_session_route_helper+, and +callback_path+.
class OidcUserAuthBaseController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[start callback verify_session]
  skip_before_action :require_mfa_if_enabled, only: %i[start callback verify_session]

  layout "application"

  def start
    if oidc_signup_start? && !signup_gate_allowed?
      redirect_to create_account_path, alert: t("account_creation.gated_oauth.verify_first")
      return
    end

    state = SecureRandom.hex(32)
    session[session_key(:state)] = state
    session[session_key(:from)] = resolve_oauth_from

    cookies.signed[session_key(:state)] = {
      value: state,
      expires: 10.minutes.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }
    cookies.signed[session_key(:from)] = {
      value: session[session_key(:from)],
      expires: 10.minutes.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }

    if session.respond_to?(:save)
      session.save
    elsif session.respond_to?(:commit)
      session.commit
    end

    auth_url = oidc_service.authorization_url(oidc_callback_redirect_uri, state)
    redirect_to auth_url, allow_other_host: true
  rescue StandardError => e
    log_oidc_start_error(e)
    redirect_to after_oidc_failure_path, alert: t("controllers.oidc_user_auth.login_failed")
  end

  def callback
    callback!
  rescue StandardError => e
    Rails.logger.error("[#{oauth_provider_label} OAuth ERROR] #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    redirect_to login_path, alert: t("controllers.oidc_user_auth.login_failed")
  end

  def verify_session
    flash.clear

    if !user_signed_in? && session[:user_id].present?
      if (u = User.find_by(id: session[:user_id]))
        sign_in(u, event: :authentication)
      end
    end

    if user_signed_in? && current_user.present?
      if current_user.oauth_primary_auth? && !session[:mfa_verified]
        session[:mfa_verified] = true
        session[:mfa_verified_at] = Time.current.to_i
      end

      if mfa_verified_for_session?
        flash.delete(:alert)
        redirect_to dashboard_path, notice: t("controllers.oidc_user_auth.signed_in_notice")
      else
        redirect_to login_path, alert: t("controllers.oidc_user_auth.complete_auth")
      end
    else
      redirect_to login_path, alert: t("controllers.oidc_user_auth.session_not_found")
    end
  end

  private

  def callback!
    restore_oidc_session_from_cookies

    if Rails.env.production? && !oidc_credentials_present?
      Rails.logger.error("[#{oauth_provider_label} OAuth ERROR] missing OAuth client configuration")
      redirect_to login_path, alert: t("controllers.oidc_user_auth.login_failed")
      return
    end

    unless params[:state].to_s == session[session_key(:state)].to_s
      cookies.delete(session_key(:state))
      cookies.delete(session_key(:from))
      redirect_to login_path, alert: t("controllers.oidc_user_auth.invalid_state")
      return
    end

    if params[:error].present?
      clear_oidc_session!
      redirect_to login_path, alert: t("controllers.oidc_user_auth.oauth_error", message: params[:error_description].presence || params[:error])
      return
    end

    if user_signed_in?
      clear_oidc_session!
      redirect_to dashboard_path
      return
    end

    redirect_uri = oidc_callback_redirect_uri
    token_data = oidc_service.exchange_code_for_token(params[:code], redirect_uri)
    access_token = token_data["access_token"]
    profile = oidc_service.user_info(access_token)

    sub = profile["sub"].presence
    if sub.blank?
      clear_oidc_session!
      redirect_to login_path, alert: t("controllers.oidc_user_auth.invalid_profile")
      return
    end

    oauth_from = session[session_key(:from)].presence || "login"
    is_signup = oauth_from == "signup"

    if is_signup && !signup_gate_allowed?
      clear_oidc_session!
      redirect_to create_account_path, alert: t("account_creation.gated_oauth.verify_first")
      return
    end

    if is_signup && signup_oauth_user.blank?
      clear_oidc_session!
      redirect_to create_account_path, alert: t("controllers.oidc_user_auth.signup_session_lost")
      return
    end

    if is_signup && signup_oauth_user.present?
      handle_gated_signup!(signup_oauth_user, profile, sub)
    else
      handle_login!(profile, sub)
    end
  end

  def handle_gated_signup!(user, profile, sub)
    provider_email = SignupEmailVerification.normalize_email(profile["email"])
    if provider_email.blank?
      clear_oidc_session!
      redirect_to create_account_choose_method_path, alert: t("controllers.oidc_user_auth.email_missing")
      return
    end

    unless provider_email_verified?(profile)
      clear_oidc_session!
      redirect_to create_account_choose_method_path, alert: t("controllers.oidc_user_auth.email_not_verified")
      return
    end

    unless provider_email == SignupEmailVerification.normalize_email(user.email)
      clear_oidc_session!
      redirect_to create_account_choose_method_path, alert: t("controllers.oidc_user_auth.email_mismatch")
      return
    end

    if User.where(user_uid_column => sub).where.not(id: user.id).exists?
      clear_oidc_session!
      redirect_to create_account_choose_method_path, alert: t("controllers.oidc_user_auth.identity_in_use")
      return
    end

    user.update!(
      user_uid_column => sub,
      auth_method: auth_method_key,
      registration_completed_at: Time.current
    )

    AccountCreation::SignupSession.clear!(session)
    OidcOAuthPrimarySession.apply!(self, user)
    clear_oidc_session!

    redirect_to send(verify_session_route_helper)
  end

  def handle_login!(profile, sub)
    existing = active_user_by_provider_uid(sub) || verified_existing_user_for_oauth(profile, sub)
    unless existing
      clear_oidc_session!
      redirect_to login_path, alert: t("controllers.oidc_user_auth.no_account")
      return
    end

    OidcOAuthPrimarySession.apply!(self, existing)
    clear_oidc_session!
    redirect_to send(verify_session_route_helper)
  end

  def active_user_by_provider_uid(sub)
    user = User.find_by(user_uid_column => sub)
    return nil unless user&.active_for_authentication?

    user
  end

  def verified_existing_user_for_oauth(profile, sub)
    provider_email = SignupEmailVerification.normalize_email(profile["email"])
    return nil if provider_email.blank?
    return nil unless provider_email_verified?(profile)

    user = User.find_by(email: provider_email)
    return nil unless user&.registration_completed_at.present?
    return nil unless user.confirmed?
    return nil unless user.signup_email_verified_at.present?
    return nil unless user.active_for_authentication?
    return nil if user.public_send(user_uid_column).present?
    return nil if User.where(user_uid_column => sub).where.not(id: user.id).exists?

    user.update!(user_uid_column => sub, auth_method: auth_method_key)
    user
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def provider_email_verified?(profile)
    truthy?(profile["email_verified"])
  end

  def signup_oauth_user
    return nil if session[:signup_user_id].blank?

    User.find_by(id: session[:signup_user_id])
  end

  def signup_gate_allowed?
    AccountCreation::SignupGate.gated_oauth_signup_allowed?(session, signup_oauth_user)
  end

  def oidc_signup_start?
    !user_signed_in? && params[:signup].present?
  end

  def resolve_oauth_from
    if params[:signup].present?
      "signup"
    elsif request.referer&.include?("sign_up") || request.referer&.include?("create_account")
      "signup"
    else
      "login"
    end
  end

  def session_key(suffix)
    :"#{oauth_session_prefix}_oauth_#{suffix}"
  end

  def restore_oidc_session_from_cookies
    if session[session_key(:state)].blank? && cookies.signed[session_key(:state)].present?
      session[session_key(:state)] = cookies.signed[session_key(:state)]
    end
    if session[session_key(:from)].blank? && cookies.signed[session_key(:from)].present?
      session[session_key(:from)] = cookies.signed[session_key(:from)]
    end
  end

  def clear_oidc_session!
    session.delete(session_key(:state))
    session.delete(session_key(:from))
    cookies.delete(session_key(:state))
    cookies.delete(session_key(:from))
  end

  def oidc_callback_redirect_uri
    if Rails.env.production?
      opts = Rails.application.config.action_controller.default_url_options
      host = opts[:host] || ENV["HOST"] || request.host
      protocol = opts[:protocol] || "https"
      "#{protocol}://#{host}#{callback_path}"
    else
      "#{request.protocol}#{request.host_with_port}#{callback_path}"
    end
  end

  def after_oidc_failure_path
    session[session_key(:from)] == "signup" ? create_account_path : login_path
  end

  def log_oidc_start_error(err)
    if Rails.env.test?
      Rails.logger.error "#{oauth_provider_label} OAuth start error: #{err.message}"
    else
      Rails.logger.error "#{oauth_provider_label} OAuth start error: #{err.message}\n#{err.backtrace&.first(8)&.join("\n")}"
    end
  end

  def oidc_service
    raise NotImplementedError
  end

  def oauth_session_prefix
    raise NotImplementedError
  end

  def oauth_provider_label
    oauth_session_prefix.to_s.camelize
  end

  def user_uid_column
    raise NotImplementedError
  end

  def auth_method_key
    raise NotImplementedError
  end

  def verify_session_route_helper
    raise NotImplementedError
  end

  def callback_path
    raise NotImplementedError
  end

  def oidc_credentials_present?
    true
  end
end
