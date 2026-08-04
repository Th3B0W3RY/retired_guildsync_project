class DiscordUserAuthController < ApplicationController
  include SignupCaptchaVerifiable

  skip_before_action :authenticate_user!, only: [ :start, :callback, :verify_session, :success ]
  skip_before_action :require_mfa_if_enabled, only: [ :start, :callback, :verify_session, :success ]
  before_action :authenticate_user!, only: [ :disconnect, :toggle_auth_method ]

  layout :determine_layout

  def start
    # Canary: confirms the request reached the server (when button "does nothing", no request is sent — failure is client-side)
    Rails.logger.info "[Discord OAuth] GET /auth/discord received referer=#{request.referer.to_s.first(120)} params=#{safe_oauth_log_params.inspect}"
    DiscordLogger.info "[Discord OAuth] GET /auth/discord received referer=#{request.referer.to_s.first(120)}" if defined?(DiscordLogger)

    # App-triggered silent re-auth (e.g. after a Discord token expired/was revoked mid-session).
    # When set we bypass the cookie silent-login path and go straight to Discord with prompt=none,
    # leaning on Discord's own session instead of our local connection (which may be gone).
    silent_reauth = params[:silent].present?

    # ========== SILENT LOGIN PATH ==========
    # Skip silent login when the user explicitly signed out (session cookie set in
    # SessionsController#destroy — cleared on browser close so returning visitors
    # get silent re-auth after reopening the browser).
    recently_signed_out = cookies.signed[:discord_signed_out].present?

    # True once we try the cookie silent-login path but it does not sign the user in
    # (missing/stale connection or refresh failure). Lets the OAuth fallback below ask
    # Discord for a silent authorize (prompt=none) instead of the full authorize screen.
    cookie_silent_attempted = false

    unless user_signed_in?
      intentional_click = params[:signup].present? || params[:popup].present? ||
                          request.referer&.include?("sign_up") || request.referer&.include?("login")

      if !silent_reauth && !recently_signed_out && (discord_uid = cookies.signed[:discord_uid]).present?
        cookie_silent_attempted = true
        silent = Discord::CookieSilentSignIn.call(discord_uid)

        if silent.signed_in?
          sign_in_user_via_discord(silent.user)

          if params[:popup].present?
            redirect_to discord_success_path(
              message: "Signed in with Discord successfully!"
            ), allow_other_host: false
            return
          else
            return redirect_to(stored_location_for(:user) || dashboard_path)
          end
        else
          # Could not silently sign in (no connection, no refresh token, or refresh failed):
          # drop the stale cookies so we do not retry a dead identity. A passive visit (no
          # explicit login/signup click) returns to the login page; an explicit click falls
          # through to the Discord OAuth redirect below (prompt=none for returning users).
          cookies.delete(:discord_uid)
          cookies.delete(:discord_seen_before)
          unless intentional_click
            redirect_to login_path
            return
          end
        end
      end
    end
    # ========== END SILENT LOGIN PATH ==========

    if discord_signup_oauth_start? && !signup_discord_flow_allowed?
      redirect_to create_account_path, alert: t("account_creation.gated_oauth.verify_first")
      return
    end

    # No stored token OR refresh failed -> normal OAuth authorization
    redirect_uri = discord_callback_redirect_uri
    state        = SecureRandom.hex(32)

    session[:discord_oauth_state]      = state
    session[:discord_oauth_link_only]  = user_signed_in? # Track if this is linking vs login
    session[:discord_oauth_from]       = if params[:signup].present?
      "signup"
    elsif request.referer&.include?("sign_up")
      "signup"
    else
      "login"
    end
    session[:discord_oauth_popup]      = params[:popup].present?

    # Decide whether to ask Discord for a silent authorize (prompt=none). Returning users
    # who already authorized the app in this browser skip the authorize screen; genuine
    # first-time signups still get Discord's default (one consent when needed). Discord-only.
    oauth_prompt =
      if params[:interactive].present?
        # One-shot interactive retry from the callback (a prior prompt=none needed user
        # interaction). Never re-request prompt=none here or the authorize would loop.
        nil
      else
        Discord::OAuthStartPrompt.new(
          silent_reauth: silent_reauth,
          oauth_from: session[:discord_oauth_from],
          link_only: user_signed_in?,
          seen_before: cookies.signed[:discord_seen_before].present?,
          has_discord_uid: cookies.signed[:discord_uid].present?,
          cookie_silent_attempted: cookie_silent_attempted
        ).call
      end

    # One-shot flag: when the authorize request used prompt=none, the callback may fall back
    # to a normal interactive OAuth exactly once if Discord reports login/consent is required.
    session[:discord_oauth_prompt_none] = oauth_prompt.present?

    # Fallback: also persist the OAuth state and origin in short-lived signed
    # cookies. Some browsers/proxies drop the Rails session cookie on the
    # cross-site redirect via Discord, which would make the callback fail
    # state validation or lose the signup/login context.
    cookies.signed[:discord_oauth_state] = {
      value: state,
      expires: 10.minutes.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }
    cookies.signed[:discord_oauth_from] = {
      value: session[:discord_oauth_from],
      expires: 10.minutes.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }

    # Ensure session is persisted before redirecting to Discord so callback can read state
    if session.respond_to?(:save)
      session.save
    elsif session.respond_to?(:commit)
      session.commit
    end

    begin
      discord_service = ::DiscordUserOAuthService.new
      # prompt is decided by Discord::OAuthStartPrompt above: "none" for returning users
      # (silent authorize) or nil for Discord's default. prompt=consent is never used here.
      # When prompt=none, Discord may return login_required/consent_required and the callback
      # retries interactively exactly once (one-shot session[:discord_oauth_prompt_none]).
      auth_url = discord_service.authorization_url(
        redirect_uri,
        state,
        prompt: oauth_prompt,
        scope: "identify guilds"
      )
      redirect_to auth_url, allow_other_host: true
    rescue => e
      # Surface operationally critical OAuth misconfiguration in server logs,
      # but keep user-facing errors generic.
      if e.message.include?("DISCORD_CLIENT_ID") || e.message.include?("DISCORD_CLIENT_SECRET")
        Rails.logger.error("[ADMIN ACTION REQUIRED] Discord OAuth is not configured. Set DISCORD_CLIENT_ID and DISCORD_CLIENT_SECRET and restart the server.")
      elsif e.message.include?("redirect URI")
        Rails.logger.error("[ADMIN ACTION REQUIRED] Discord OAuth redirect URI mismatch. Ensure this URI is in Discord OAuth2 settings: #{redirect_uri}")
      end

      if Rails.env.test?
        # In test environment, only log the error message to reduce log clutter
        Rails.logger.error "Discord OAuth start error: #{e.message}"
      else
        # In other environments, log full backtrace for debugging
        Rails.logger.error "Discord OAuth start error: #{e.message}\n#{e.backtrace.join("\n")}"
      end

      error_message = t("controllers.discord_user_auth.login_failed")

      if popup_request?
        render "callback_error", locals: { error: error_message }, layout: false
      else
        redirect_path = session[:discord_oauth_from] == "signup" ? sign_up_path : login_path
        redirect_to redirect_path, alert: error_message
      end
    end
  end

  def callback
    begin
      callback!
    rescue => e
      Rails.logger.error("[Discord OAuth ERROR] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
      if params[:popup].present?
        render "callback_error", locals: { error: t("controllers.discord_user_auth.login_failed") }, layout: false
      else
        redirect_to login_path, alert: t("controllers.discord_user_auth.login_failed")
      end
    end
  end

  def callback!
    # Temporary logging (remove after Discord OAuth confirmed working)
    Rails.logger.info("[Discord OAuth] Params: #{safe_oauth_log_params.inspect}")
    Rails.logger.info("[Discord OAuth] ENV check: ID present=#{ENV['DISCORD_CLIENT_ID'].present?}")

    # Validate required ENV in production; redirect safely instead of crashing
    if Rails.env.production?
      unless ENV["DISCORD_CLIENT_ID"].present? && ENV["DISCORD_CLIENT_SECRET"].present?
        Rails.logger.error("[Discord OAuth ERROR] DISCORD_CLIENT_ID or DISCORD_CLIENT_SECRET missing")
        safe_oauth_failed_redirect(params[:popup].present?)
        return
      end
      unless ENV["FRONTEND_URL"].present?
        Rails.logger.warn("[Discord OAuth] FRONTEND_URL not set; error redirect will use login_path")
      end
    end

    # If the Rails session cookie was lost between /auth/discord and the callback,
    # try to restore state and origin from the signed cookies.
    if session[:discord_oauth_state].blank? && cookies.signed[:discord_oauth_state].present?
      session[:discord_oauth_state] = cookies.signed[:discord_oauth_state]
      Rails.logger.info "[Discord OAuth] Restored state from signed cookie in callback"
    end
    if session[:discord_oauth_from].blank? && cookies.signed[:discord_oauth_from].present?
      session[:discord_oauth_from] = cookies.signed[:discord_oauth_from]
      Rails.logger.info "[Discord OAuth] Restored oauth_from from signed cookie in callback"
    end

    # Verify state
    unless params[:state] == session[:discord_oauth_state]
      session.delete(:discord_oauth_prompt_none)
      cookies.delete(:discord_oauth_state)
      cookies.delete(:discord_oauth_from)
      if popup_request?
        render "callback_error", locals: { error: t("controllers.discord_user_auth.invalid_state") }, layout: false
      else
        redirect_to login_path, alert: t("controllers.discord_user_auth.invalid_state")
      end
      return
    end

    # Handle OAuth errors (e.g. user denied)
    if params[:error].present?
      # Silent (prompt=none) re-auth failed because Discord needs interaction. Retry once
      # with a normal interactive OAuth (the flag is cleared so the retry cannot loop).
      if session.delete(:discord_oauth_prompt_none) &&
         %w[login_required consent_required interaction_required].include?(params[:error].to_s)
        retry_was_popup = popup_request?
        session.delete(:discord_oauth_state)
        cookies.delete(:discord_oauth_state)
        cookies.delete(:discord_oauth_from)
        Rails.logger.info "[Discord OAuth] prompt=none requires interaction (#{params[:error]}); retrying interactively"
        # Preserve popup context so a popup login does not break out into a full-page flow.
        retry_params = { interactive: 1 }
        retry_params[:popup] = 1 if retry_was_popup
        redirect_to discord_login_path(retry_params)
        return
      end

      error_msg = params[:error_description] || params[:error]
      if popup_request?
        render "callback_error", locals: { error: user_signed_in? ? t("controllers.discord_user_auth.connection_failed", error: error_msg) : t("controllers.discord_user_auth.oauth_error_login", error: error_msg) }, layout: false
      elsif user_signed_in?
        redirect_to account_settings_path, alert: t("controllers.discord_user_auth.connection_failed", error: error_msg)
      else
        redirect_to login_path, alert: t("controllers.discord_user_auth.oauth_error_login", error: error_msg)
      end
      return
    end

    # Build redirect_uri: in production use default_url_options so it matches https://guild-sync.net
    redirect_uri = discord_callback_redirect_uri

    Rails.logger.info "Discord callback received code=present state=present redirect_uri=#{redirect_uri}"

    begin
      discord_service = ::DiscordUserOAuthService.new
      token_data      = discord_service.exchange_code_for_token(params[:code], redirect_uri)
      Rails.logger.info "Discord callback token exchange success"
      user_info       = discord_service.get_user_info(token_data["access_token"])

      # Build Discord username (support old discriminator style)
      discord_username = user_info["username"]
      if user_info["discriminator"].present? && user_info["discriminator"] != "0"
        discord_username = "#{user_info['username']}##{user_info['discriminator']}"
      end

      avatar_url = discord_service.avatar_url(user_info["id"], user_info["avatar"])

      # Check if this is a popup request BEFORE processing
      is_popup = popup_request?

      # Check if Discord account is already connected to a different user
      existing_connection = UserDiscordConnection.find_by(discord_user_id: user_info["id"])
      existing_user_by_discord_id = User.find_by(discord_user_id: user_info["id"])

      if user_signed_in?
        # Linking Discord account to existing user
        # Check if already connected to a different user
        if existing_connection && existing_connection.user != current_user
          error_message = t("controllers.discord_user_auth.already_connected")
          if is_popup
            render "callback_error", locals: { error: error_message }, layout: false
          else
            redirect_to account_settings_path, alert: error_message
          end
          return
        end

        if existing_user_by_discord_id && existing_user_by_discord_id != current_user
          error_message = t("controllers.discord_user_auth.already_connected")
          if is_popup
            render "callback_error", locals: { error: error_message }, layout: false
          else
            redirect_to account_settings_path, alert: error_message
          end
          return
        end

        link_discord_to_user(current_user, user_info, discord_username, avatar_url)

        # Persist Discord OAuth tokens
        persist_discord_connection(current_user, token_data, user_info["id"])

        begin
          InteractionMigrator.new(user: current_user, discord_user_id: user_info["id"]).migrate_all!
        rescue => e
          Rails.logger.warn "InteractionMigrator failed (non-fatal): #{e.message}"
        end

        cookies.signed[:discord_seen_before] = {
          value: "1",
          expires: 30.days.from_now,
          httponly: true,
          same_site: :lax,
          secure: Rails.env.production?
        }

        cookies.signed[:discord_uid] = {
          value: user_info["id"],
          expires: 30.days.from_now,
          httponly: true,
          same_site: :lax,
          secure: Rails.env.production?
        }

        cookies.delete(:discord_signed_out)

        session.delete(:discord_oauth_state)
        session.delete(:discord_oauth_link_only)
        session.delete(:discord_oauth_popup)
        session.delete(:discord_oauth_prompt_none)
        cookies.delete(:discord_oauth_state)
        cookies.delete(:discord_oauth_from)

        if is_popup
          # Redirect to success page for popup (ensures session cookie is accessible)
          redirect_to discord_success_path(
            message: t("controllers.discord_user_auth.linked_successfully"),
            username: discord_username
          ), allow_other_host: false
          nil  # CRITICAL: Stop execution here
        else
          redirect_to account_settings_path, notice: t("controllers.discord_user_auth.linked_successfully")
        end
      else
        # Login or signup flow
        oauth_from = session[:discord_oauth_from] || "login"
        is_signup  = oauth_from == "signup"

        Rails.logger.info "Discord OAuth callback - from: #{oauth_from}, is_signup: #{is_signup}"

        if is_signup && !signup_discord_flow_allowed?
          redirect_to create_account_path, alert: t("account_creation.gated_oauth.verify_first")
          return
        end

        # Sign up with Discord: if this Discord is already linked to an account, send them to sign in
        if (existing_connection || existing_user_by_discord_id) && is_signup
          error_message = t("controllers.discord_user_auth.already_has_account")
          if is_popup
            render "callback_error", locals: { error: error_message }, layout: false
          else
            redirect_to login_path, notice: error_message
          end
          return
        end

        user = nil
        begin
          if is_signup && signup_discord_user.present?
            Rails.logger.info "[Discord OAuth] Step: completing gated Discord signup"
            user = complete_gated_discord_signup(signup_discord_user, user_info, discord_username, avatar_url)
          elsif is_signup
            Rails.logger.info "[Discord OAuth] Step: creating user from Discord signup"
            user = find_or_create_user_from_discord(user_info, discord_username, avatar_url, allow_create: true)
          else
            Rails.logger.info "[Discord OAuth] Step: finding existing user from Discord login"
            user = find_user_from_discord(user_info, discord_username, avatar_url)

            unless user
              Rails.logger.info "[Discord OAuth] No existing account — auto-creating from login flow"
              user = find_or_create_user_from_discord(user_info, discord_username, avatar_url, allow_create: true)
            end
          end
        rescue => e
          Rails.logger.error "[Discord OAuth] User find/create crashed: #{e.class}: #{e.message}"
          Rails.logger.error e.backtrace&.first(5)&.join("\n")
          redirect_path = is_signup ? sign_up_path : login_path
          redirect_to redirect_path, alert: t("controllers.discord_user_auth.create_failed")
          return
        end

        Rails.logger.info "[Discord OAuth] User found/created: #{user.present? ? "yes (id: #{user.id})" : "no"}"

        unless user
          base_msg = t("controllers.discord_user_auth.create_failed")
          detail = @discord_signup_errors.present? ? " [#{@discord_signup_errors}]" : ""
          if popup_request?
            render "callback_error", locals: { error: base_msg + detail }, layout: false
          else
            redirect_to sign_up_path, alert: base_msg + detail
          end
          return
        end

        begin
          persist_discord_connection(user, token_data, user_info["id"])
        rescue => e
          Rails.logger.error "persist_discord_connection failed (non-fatal): #{e.class}: #{e.message}"
        end

        begin
          InteractionMigrator.new(user: user, discord_user_id: user_info["id"]).migrate_all!
        rescue => e
          Rails.logger.warn "InteractionMigrator failed (non-fatal): #{e.message}"
        end

        cookies.signed[:discord_seen_before] = {
          value: "1",
          expires: 30.days.from_now,
          httponly: true,
          same_site: :lax,
          secure: Rails.env.production?
        }

        cookies.signed[:discord_uid] = {
          value: user_info["id"],
          expires: 30.days.from_now,
          httponly: true,
          same_site: :lax,
          secure: Rails.env.production?
        }

        cookies.delete(:discord_signed_out)

        session.delete(:discord_oauth_state)
        session.delete(:discord_oauth_link_only)
        session.delete(:discord_oauth_from)
        session.delete(:discord_oauth_popup)
        session.delete(:discord_oauth_prompt_none)
        AccountCreation::SignupSession.clear!(session) if is_signup
        cookies.delete(:discord_oauth_state)
        cookies.delete(:discord_oauth_from)

        sign_in_user_via_discord(user)

        if is_popup
          flash.clear
          redirect_to discord_success_path(
            message: t("controllers.discord_user_auth.signed_in_successfully"),
            username: discord_username
          ), allow_other_host: false
        else
          redirect_to discord_verify_session_path
        end
      end
    rescue Discord::DiscordTokenExpiredError, Discord::DiscordTokenRevokedError => e
      Rails.logger.error "Discord token error: #{e.message}"
      if user_signed_in?
        current_user.user_discord_connection&.destroy
        redirect_to account_settings_path, alert: t("controllers.discord_user_auth.token_revoked_reconnect")
      else
        redirect_to login_path, alert: t("controllers.discord_user_auth.token_revoked_signin")
      end
    rescue => e
      if Rails.env.test?
        Rails.logger.error "Discord OAuth callback error: #{e.message}"
      else
        Rails.logger.error "Discord OAuth callback error: #{e.message}\n#{e.backtrace&.first(12)&.join("\n")}"
      end

      is_popup = params[:popup].present? || (session[:discord_oauth_popup] rescue false)
      oauth_from = (session[:discord_oauth_from] rescue nil) || "login"

      if is_popup
        error_message = if user_signed_in?
          t("controllers.discord_user_auth.link_failed", error: e.message)
        else
          oauth_from == "signup" ? t("controllers.discord_user_auth.create_failed") : t("controllers.discord_user_auth.login_failed")
        end
        render "callback_error", locals: { error: error_message }, layout: false
        return
      end

      if user_signed_in?
        redirect_to account_settings_path, alert: t("controllers.discord_user_auth.link_failed", error: "unknown error")
        return
      end

      redirect_path = oauth_from == "signup" ? sign_up_path : login_path
      alert_key = oauth_from == "signup" ? "controllers.discord_user_auth.create_failed" : "controllers.discord_user_auth.login_failed"
      redirect_to redirect_path, alert: t(alert_key)
      nil
    end
  end

  def disconnect
    unless user_signed_in?
      redirect_to login_path, alert: t("controllers.discord_user_auth.must_be_signed_in")
      return
    end

    user = current_user

    if user.auth_method == "discord"
      redirect_to account_settings_path, alert: t("controllers.discord_user_auth.cannot_disconnect_discord_auth")
      return
    end

    user.user_discord_connection&.destroy

    user.update!(
      discord_user_id: nil,
      discord_username: nil,
      discord_avatar_url: nil,
      discord_connected: false
    )

    # Clear cookies so silent login is disabled
    cookies.delete(:discord_uid)
    cookies.delete(:discord_seen_before)

    redirect_to account_settings_path, notice: t("controllers.discord_user_auth.disconnected_successfully")
  end

  def success
    # This page is loaded in the popup after successful OAuth
    # The user is already signed in (session was set in callback)
    # This page sends message to parent and closes itself

    unless user_signed_in?
      # If somehow not signed in, redirect to login
      if popup_request?
        render "callback_error", locals: { error: t("controllers.discord_user_auth.session_not_found") }, layout: false
      else
        redirect_to login_path, alert: t("controllers.discord_user_auth.session_not_found")
      end
      return
    end

    # Render success page that will communicate with parent and close
    render "callback_success", locals: {
      message: params[:message] || "Discord authentication successful!",
      username: params[:username],
      redirect_to: dashboard_path
    }, layout: false
  end

  def verify_session
    # This endpoint is used to verify session after popup or non-popup Discord login.
    # It already has skip_before_action at class level, so no auth required.

    # Clear any stale flash messages first
    flash.clear

    Rails.logger.info "[Discord OAuth] verify_session start: user_signed_in?=#{user_signed_in?}, session_user_id=#{session[:user_id].inspect}, discord_uid_cookie=#{cookies.signed[:discord_uid].inspect}"

    # Primary recovery path: if Warden lost its state but we still have a backup
    # user_id in the session, restore the Devise session from that.
    if !user_signed_in? && session[:user_id].present?
      if (u = User.find_by(id: session[:user_id]))
        Rails.logger.info "[Discord OAuth] verify_session: restoring user from session[:user_id]=#{session[:user_id]}"
        sign_in(u, event: :authentication)
      end
    end

    # Secondary recovery path: if session[:user_id] is missing but we have a
    # Discord UID cookie (set during OAuth callback), restore the user from that.
    if !user_signed_in? && cookies.signed[:discord_uid].present?
      if (u = User.find_by(discord_user_id: cookies.signed[:discord_uid]))
        Rails.logger.info "[Discord OAuth] verify_session: restoring user from cookies.signed[:discord_uid]=#{cookies.signed[:discord_uid]}"
        sign_in(u, event: :authentication)
        session[:user_id] = u.id
      end
    end

    if user_signed_in? && current_user.present?
      # Ensure MFA verification is set for Discord users
      if current_user.oauth_primary_auth? && !session[:mfa_verified]
        session[:mfa_verified] = true
        session[:mfa_verified_at] = Time.current.to_i
      end

      # Check if fully authenticated
      if mfa_verified_for_session?
        # Clear any stale alerts before redirecting
        flash.delete(:alert)
        redirect_to dashboard_path, notice: t("controllers.discord_user_auth.signed_in_notice")
      else
        redirect_to login_path, alert: t("controllers.discord_user_auth.complete_auth")
      end
    else
      Rails.logger.warn "[Discord OAuth] verify_session: no valid session after recovery attempts"
      redirect_to login_path, alert: t("controllers.discord_user_auth.session_not_found_signin")
    end
  end

  def toggle_auth_method
    unless user_signed_in?
      redirect_to login_path, alert: t("controllers.discord_user_auth.must_be_signed_in_toggle")
      return
    end

    user = current_user

    # Switching FROM Discord → MFA
    if params[:auth_method] == "mfa"
      if !user.mfa_enabled?
        redirect_to mfa_setup_path, alert: t("controllers.discord_user_auth.setup_mfa_first")
        return
      end
      user.update!(auth_method: "mfa")
      redirect_to account_settings_path, notice: t("controllers.discord_user_auth.mfa_updated")
      return
    end

    # Switching FROM MFA → Discord
    if params[:auth_method] == "discord"
      if user.discord_connected?
        user.update!(auth_method: "discord")
        redirect_to account_settings_path, notice: t("controllers.discord_user_auth.discord_updated")
      else
        redirect_to account_settings_path, alert: t("controllers.discord_user_auth.connect_discord_first")
      end
      return
    end

    redirect_to account_settings_path, alert: t("controllers.discord_user_auth.invalid_auth_method")
  end

  private

  def signup_discord_flow_allowed?
    AccountCreation::SignupGate.gated_oauth_signup_allowed?(session, signup_discord_user)
  end

  def signup_discord_user
    return nil if session[:signup_user_id].blank?

    User.find_by(id: session[:signup_user_id])
  end

  def complete_gated_discord_signup(user, user_info, discord_username, avatar_url)
    link_discord_to_user(user, user_info, discord_username, avatar_url)
    user.update!(
      auth_method: :discord,
      registration_completed_at: Time.current
    )
    user
  end

  def link_discord_to_user(user, user_info, discord_username, avatar_url)
    # Note: This check is now done in the callback method before calling this,
    # but keeping it here as a safety check
    existing_connection = UserDiscordConnection.find_by(discord_user_id: user_info["id"])
    if existing_connection && existing_connection.user != user
      raise t("controllers.discord_user_auth.already_connected")
    end

    existing_user = User.find_by(discord_user_id: user_info["id"])
    if existing_user && existing_user != user
      raise t("controllers.discord_user_auth.already_connected")
    end

    user.update!(
      discord_user_id: user_info["id"],
      discord_username: discord_username,
      discord_avatar_url: avatar_url,
      discord_connected: true,
      discord_global_name: user_info["global_name"].presence
    )
  end

  def find_user_from_discord(user_info, discord_username, avatar_url)
    # First try to find by discord_user_id on User model
    user = User.find_by(discord_user_id: user_info["id"])

    # If not found, try to find via UserDiscordConnection
    unless user
      connection = UserDiscordConnection.find_by(discord_user_id: user_info["id"])
      user = connection&.user
    end

    if user
      user.update(
        discord_username: discord_username,
        discord_avatar_url: avatar_url,
        discord_connected: true
      )
    end

    user
  end

  def find_or_create_user_from_discord(user_info, discord_username, avatar_url, allow_create: false)
    user = User.find_by(discord_user_id: user_info["id"])

    if user
      user.update(
        discord_username: discord_username,
        discord_avatar_url: avatar_url,
        discord_connected: true,
        discord_global_name: user_info["global_name"].presence
      )
      return user
    end

    return nil unless allow_create

    base_email = "#{user_info['username']}_#{user_info['id']}@discord.guildsync.local"
    email      = base_email
    counter    = 1
    while User.exists?(email: email)
      email = "#{user_info['username']}_#{user_info['id']}_#{counter}@discord.guildsync.local"
      counter += 1
    end

    base_username = user_info["username"].to_s.downcase.gsub(/[^a-z0-9_]/, "_").gsub(/_{2,}/, "_").gsub(/\A_|_\z/, "")
    base_username = "discord_#{user_info['id'].to_s.last(6)}" if base_username.length < 3
    base_username = base_username[0, 30]
    username      = base_username
    counter       = 1
    while User.exists?(username: username)
      username = "#{base_username}_#{counter}"[0, 30]
      counter += 1
    end

    selected_plan_id = session[:selected_plan_id] || params[:plan_id]
    plan = nil
    if selected_plan_id.present? && defined?(PricingPlan) && PricingPlan.table_exists?
      plan = PricingPlan.find_by(id: selected_plan_id)
    end

    user_attributes = {
      email: email,
      username: username,
      password: SecureRandom.hex(32),
      discord_user_id: user_info["id"],
      discord_username: discord_username,
      discord_avatar_url: avatar_url,
      discord_connected: true,
      auth_method: :discord,
      discord_global_name: user_info["global_name"].presence
    }

    user = User.new(user_attributes)
    if plan && plan.name != "Free"
      user.trial_selected_at_signup = true
    end

    # Discord has already verified the user can access this email via OAuth.
    user.skip_confirmation!

    unless user.save
      error_details = user.errors.full_messages.join(", ")
      Rails.logger.error "[Discord OAuth] User validation failed: #{error_details}"
      @discord_signup_errors = error_details
      return nil
    end
    Rails.logger.info "Successfully created Discord user with id: #{user.id}"

    if plan && plan.name != "Free"
      begin
        user.create_trial_at_signup!(plan)
        Rails.logger.info "Created 14-day trial for Discord user #{user.id} with plan #{plan.name}"
      rescue => e
        Rails.logger.error "Failed to create trial for Discord signup: #{e.message}"
        user.ensure_free_plan_subscription unless user.subscriptions.current.exists?
      end
    else
      user.ensure_free_plan_subscription unless user.subscriptions.current.exists?
    end

    user
  end

  def persist_discord_connection(user, token_data, discord_user_id)
    expires_at = token_data["expires_in"] ? Time.current + token_data["expires_in"].seconds : nil
    connection = user.user_discord_connection

    if connection
      connection.update!(
        discord_user_id: discord_user_id,
        access_token: token_data["access_token"],
        refresh_token: token_data["refresh_token"] || connection.refresh_token,
        expires_at: expires_at,
        scopes: token_data["scope"] || "identify"
      )
    else
      user.create_user_discord_connection!(
        discord_user_id: discord_user_id,
        access_token: token_data["access_token"],
        refresh_token: token_data["refresh_token"],
        expires_at: expires_at,
        scopes: token_data["scope"] || "identify"
      )
    end

    Rails.logger.info "Persisted Discord connection for user #{user.id} (expires at: #{expires_at})"
  rescue => e
    Rails.logger.error "Failed to persist Discord connection for user #{user.id}: #{e.class}: #{e.message}"
    raise
  end

  def sign_in_user_via_discord(user)
    Discord::OAuthPrimarySession.apply!(self, user)
  end

  def determine_layout
    popup_request? ? "popup" : "application"
  end

  def discord_signup_oauth_start?
    !user_signed_in? && params[:signup].present?
  end

  def popup_request?
    session[:discord_oauth_popup] || params[:popup].present?
  end

  def safe_oauth_log_params
    params.to_unsafe_h.slice("state", "popup", "signup", "error")
  end

  # Redirect to login with oauth_failed; never raises. Used when callback must not crash (e.g. 502 prevention).
  def safe_oauth_failed_redirect(popup)
    if popup
      render "callback_error", locals: { error: "Discord login failed. Please try again." }, layout: false
    else
      url = ENV["FRONTEND_URL"].presence
      url = "#{url}/login?error=oauth_failed" if url.present?
      url = login_path if url.blank?
      redirect_to url, allow_other_host: ENV["FRONTEND_URL"].present?, alert: "Discord login failed. Please try again."
    end
  end

  # Callback URL for Discord OAuth. In production use default_url_options so it matches https://guild-sync.net.
  def discord_callback_redirect_uri
    if Rails.env.production?
      opts = Rails.application.config.action_controller.default_url_options
      host = opts[:host] || ENV["HOST"] || request.host
      protocol = opts[:protocol] || "https"
      "#{protocol}://#{host}/auth/discord/callback"
    else
      "#{request.protocol}#{request.host_with_port}/auth/discord/callback"
    end
  end
end
