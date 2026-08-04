class ApplicationController < ActionController::Base
  include Devise::Controllers::Helpers
  include Pundit::Authorization
  include MfaVerification
  include EnsureVerifiedRealEmail

  protect_from_forgery with: :exception

  # Handle CSRF errors gracefully for JSON requests
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_csrf_error

  # Make permission helper methods available in views
  helper_method :can_manage_roles?, :can_manage_applications?, :can_manage_guild_settings?, :can_kick_members?, :can_manage_warnings?, :can_manage_tags?, :can_manage_events?, :can_manage_polls?, :can_manage_loot_rolls?, :can_manage_discord_channels?, :can_view_activity_feed?, :can_export_members_csv?, :can_use_message_center?, :user_has_higher_authority_than?, :can_manage_gear_requests?, :can_edit_gear_scanned_stats?, :can_view_gear?, :can_manage_documents?, :can_manage_files?, :admin_user?, :support_center_url, :flash_toast_duration_ms, :plan_allows?, :guild_ai_stat_scanner_entitled?, :alliance_owner_in_active_guild?, :alliance_custom_manager_in_active_guild?, :alliance_active_member_guilds, :can_manage_alliance_actions?, :can_invite_alliance_actions?, :can_kick_alliance_actions?, :can_edit_member_snapshot_data?, :can_view_member_gear_stats?

  before_action :set_locale
  before_action :set_request_variant
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :validate_session, unless: :public_page?
  before_action :authenticate_user!, unless: :public_page?
  before_action :check_credentials_setup_required, unless: :public_page?
  before_action :require_mfa_if_enabled, unless: :public_page?
  before_action :ensure_fully_authenticated, unless: :public_page?
  after_action :track_user_activity, if: :track_user_activity?
  after_action :append_locale_debug_headers, if: :gs_locale_debug_headers?

  def support_center_url
    SiteSetting.release_notes_url
  end

  def flash_toast_duration_ms
    SiteSetting.flash_toast_duration_ms
  end

  def plan_allows?(feature)
    current_user&.plan_allows?(feature)
  end

  # Guild stat scanner: own plan, or guild owner’s paid plan (shared OCR pool via Ocr::BillingSubject).
  def guild_ai_stat_scanner_entitled?(guild)
    return false unless guild&.owner && current_user
    return true if current_user.plan_allows?(:ai_gear_scanner)

    PlanEntitlementService.allowed?(guild.owner, :ai_gear_scanner)
  end

  protected

  # JSON/XHR and gear upload must not receive HTML redirects (302 login/MFA).
  def json_api_request?
    request.format.json? ||
      request.headers["Accept"].to_s.include?("application/json") ||
      (controller_name == "gear" && action_name == "upload")
  end

  def render_json_auth_error(message_key, status: :unauthorized)
    render json: { error: t(message_key) }, status: status
    false
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :username ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :username ])
  end

  def after_sign_in_path_for(resource)
    dashboard_path
  end

  def sanitize_text_input(value)
    return nil if value.nil?

    stripped = ActionController::Base.helpers.strip_tags(value.to_s)
    CGI.unescapeHTML(stripped).strip
  end

  def sanitize_search_input(value)
    sanitized = sanitize_text_input(value)
    return "" if sanitized.blank?

    ActiveRecord::Base.sanitize_sql_like(sanitized)
  end

  def sanitize_permitted_text_fields!(permitted_params, fields)
    fields.each do |field|
      next unless permitted_params.key?(field)

      permitted_params[field] = sanitize_text_input(permitted_params[field])
    end

    permitted_params
  end

  # SiteSetting-driven redirects must be http(s) with a real host to mitigate open redirects.
  def redirect_to_trusted_site_setting_url(url_string, fallback: root_path, **redirect_options)
    safe = Guildsync::ExternalRedirectUrl.build!(url_string)
    redirect_to safe, **redirect_options.merge(allow_other_host: true)
  rescue Guildsync::ExternalRedirectUrl::Invalid
    redirect_to fallback, alert: t("controllers.application.invalid_external_redirect")
  end

  def log_security_event(event:, status:, actor: nil, subject: nil, metadata: {})
    resolved_actor = actor
    if resolved_actor.nil?
      resolved_actor = current_user
    end

    SecurityAuditLogger.log(
      event: event,
      status: status,
      actor: resolved_actor,
      subject: subject,
      request: request,
      metadata: metadata
    )
  rescue Devise::MissingWarden
    SecurityAuditLogger.log(
      event: event,
      status: status,
      actor: actor,
      subject: subject,
      request: request,
      metadata: metadata
    )
  end

  private

  # Serve *.html+mobile.erb for HTML requests from phone/tablet UAs (Rails request.variant).
  def set_request_variant
    return unless request.format.html?
    return if request.path.start_with?("/admin")

    request.variant = :mobile if mobile_browser_request?
  end

  def mobile_browser_request?
    ua = request.user_agent.to_s
    return false if ua.blank?

    ua.match?(/iPhone|iPod|webOS|BlackBerry|IEMobile|Opera Mini/i) ||
      ua.match?(/Android.*Mobile/i) ||
      (ua.include?("Android") && !ua.include?("Tablet")) ||
      ua.match?(/\bMobile\b/i)
  end

  def set_locale
    locale = locale_from_param ||
             locale_from_user ||
             locale_from_browser ||
             I18n.default_locale

    I18n.locale = locale
  end

  # Explicit query param (?locale=de) — also persists to session
  def locale_from_param
    locale = params[:locale]
    return unless locale.present? && I18n.available_locales.include?(locale.to_sym)

    session[:locale] = locale
    locale.to_sym
  end

  # Signed-in: use saved preferred_locale if set.
  # If preference is blank ("Default" in settings), do not use session[:locale] — it may be stale from
  # old ?locale= clicks and would override the intended app default.
  # Guests: use session[:locale] from header language picks.
  def locale_from_user
    if current_user&.preferred_locale.present?
      current_user.preferred_locale.to_sym
    elsif current_user
      nil
    elsif session[:locale].present? && I18n.available_locales.include?(session[:locale].to_sym)
      session[:locale].to_sym
    end
  end

  # Browser Accept-Language. Skipped for signed-in users with no explicit preferred_locale so the app
  # defaults to :en instead of following de-DE etc. on every visit (header ?locale= still wins first).
  def locale_from_browser
    return if current_user && current_user.preferred_locale.blank?

    http_accept_language.compatible_language_from(I18n.available_locales)
  end

  # Opt-in response headers for diagnosing mixed-locale / Accept-Language issues (staging or local).
  # Set GS_LOCALE_DEBUG=1. In production, also set GS_LOCALE_DEBUG_PRODUCTION_OK=1 (short-lived RCA only).
  def gs_locale_debug_headers?
    return false if Rails.env.test?
    return false unless ENV["GS_LOCALE_DEBUG"] == "1"
    return true if Rails.env.development?
    return true if Rails.env.staging?

    ENV["GS_LOCALE_DEBUG_PRODUCTION_OK"] == "1"
  end

  def append_locale_debug_headers
    return unless request.format.html?

    al = request.env["HTTP_ACCEPT_LANGUAGE"].to_s.delete("\r\n")
    al = al.byteslice(0, 500) if al.length > 500

    response.set_header("X-GuildSync-Locale", I18n.locale.to_s)
    response.set_header("X-GuildSync-Session-Locale", session[:locale].to_s)
    response.set_header("X-GuildSync-Params-Locale", params[:locale].to_s)
    response.set_header("X-GuildSync-Accept-Language", al)
    response.set_header("X-GuildSync-User-Preferred-Locale", current_user&.preferred_locale.to_s)
    response.set_header("X-GuildSync-Controller-Action", "#{controller_name}##{action_name}")
  end

  def public_page?
    # Public pages that don't require authentication
    # Share pages for documents are public (handled by controller)
    return true if controller_name == "guild_documents" && action_name == "share"
    return true if controller_name == "join" && action_name == "show"
    (controller_name == "home" && action_name.in?(%w[landing pricing])) ||
    (controller_name == "footer_support_links" && action_name.in?(%w[documentation contact discord])) ||
    (controller_name == "homepage_features" && action_name == "show") ||
    (controller_name == "marketing_legal_pages" && action_name == "show") ||
    (controller_name == "settings" && action_name == "release_notes") ||
    (controller_name == "roadmap" && action_name.in?(%w[index show])) ||
    (controller_name == "pricing" && action_name.in?(%w[public_pricing select_plan])) ||
    (controller_name == "account_creation") ||
    # Use controller_path so Admin::SessionsController (/admin/login) is not treated as guest public shell.
    (controller_path == "sessions" && action_name.in?(%w[new create])) ||
    (controller_name == "registrations" && action_name.in?(%w[new create])) ||
    (controller_name == "confirmations" && action_name.in?(%w[new create show])) ||
    (controller_name == "passwords" && action_name.in?(%w[new create edit update])) ||
      (controller_name == "backup_codes" && action_name == "verify") ||
      (controller_name == "recoveries" && action_name.in?(%w[edit update])) ||
    (controller_name == "discord_user_auth" && action_name.in?(%w[start callback verify_session success])) ||
    (controller_name == "google_user_auth" && action_name.in?(%w[start callback verify_session])) ||
    (controller_name == "microsoft_user_auth" && action_name.in?(%w[start callback verify_session])) ||
    (controller_path == "stripe/webhooks" && action_name == "receive") ||
    (controller_name == "discord_webhooks" && action_name.in?(%w[interactions create])) ||
    (controller_name == "discord_event_signups" && action_name == "webhook")
  end

  def require_mfa_if_enabled
    # Only check MFA for authenticated users with valid current_user
    return unless user_signed_in? && current_user.present?
    return if skip_mfa_check?

    # Discord auth users don't need MFA - they're verified via Discord OAuth.
    # Always refresh the timestamp so mfa_verified_for_session? stays true for the
    # lifetime of the browser session (not just the first 30 minutes).
    if current_user.oauth_primary_auth?
      # Discord-primary sessions must respect Discord token expiry/revocation: if the
      # stored token is expired and cannot be refreshed, force a fresh Discord OAuth.
      # Google/Microsoft OAuth and MFA users are intentionally untouched here.
      return if current_user.discord? && discord_session_reauth_required?

      session[:mfa_verified]    = true
      session[:mfa_verified_at] = Time.current.to_i
      return
    end

    # MFA is mandatory for MFA auth method users - always check
    # If MFA is not set up, redirect to setup
    if !current_user.mfa_enabled? || !current_user.mfa_verified?
      if json_api_request?
        return render_json_auth_error("gear.api.mfa_required", status: :forbidden)
      end
      redirect_to mfa_setup_path, alert: t('controllers.application.mfa.complete_setup')
      return
    end

    # In test environment, check if user has skip_mfa_verification flag set
    # If so, auto-set session verification (for integration tests)
    if Rails.env.test? && User.skip_mfa_verification?(current_user.id)
      unless session[:mfa_verified]
        session[:mfa_verified] = true
        session[:mfa_verified_at] = Time.current.to_i
      end
      return
    end

    # MFA is enabled and verified - check session verification
    unless session[:mfa_verified]
      if json_api_request?
        return render_json_auth_error("gear.api.mfa_required", status: :forbidden)
      end
      redirect_to mfa_verification_path(return_to: request.path), alert: t('controllers.application.mfa.verify_identity')
      return
    end

    # Check if verification is still valid (30 minutes)
    if session[:mfa_verified_at]
      verified_at = Time.at(session[:mfa_verified_at])
      if verified_at < 30.minutes.ago
        if json_api_request?
          return render_json_auth_error("gear.api.mfa_required", status: :forbidden)
        end
        redirect_to mfa_verification_path(return_to: request.path), alert: t('controllers.application.mfa.session_expired')
        nil
      end
    end
  end

  def skip_mfa_check?
    return true if controller_name.in?(%w[mfa_setup mfa_verification sessions registrations passwords discord_user_auth google_user_auth microsoft_user_auth profile_completion])
    return true if public_page?
    false
  end

  # Returns true (and issues a redirect) when a Discord-primary user's stored token is
  # expired and could not be refreshed. Only acts on full-page GET navigations so we
  # never disrupt JSON/Turbo POSTs mid-action; the next page load re-checks.
  def discord_session_reauth_required?
    return false unless request.get? && request.format.html? && !request.xhr?

    result = Discord::AuthSessionValidator.new(current_user).call
    return false unless result.reauth_required?

    enforce_discord_reauth!
    true
  end

  # Clears the GuildSync session for a Discord-primary user whose Discord token is no
  # longer valid and sends them into a silent (prompt=none) Discord re-authentication.
  # Deliberately does NOT set discord_signed_out, so silent re-login is allowed here.
  def enforce_discord_reauth!
    Rails.logger.info("[Discord auth] forcing re-auth for user #{current_user&.id} (expired/revoked token)")
    session.delete(:mfa_verified)
    session.delete(:mfa_verified_at)
    session.delete(:user_id)
    cookies.delete(:discord_uid)
    # Intentionally keep :discord_seen_before so a subsequent manual "Sign in with Discord"
    # is treated as a returning user (prompt=none) rather than a brand-new authorization.
    # Only explicit Disconnect clears that cookie.
    sign_out(:user)
    reset_session
    redirect_to discord_login_path(silent: 1), alert: t("controllers.discord_user_auth.token_revoked_signin")
  end

  def check_credentials_setup_required
    # Profile completeness before optional TOTP setup is enforced in
    # +MfaSetupController#check_profile_complete+ (+MfaSetupController+ skips this callback).
    return unless user_signed_in? && current_user.present?
    return if public_page?
    return if controller_name == "profile_completion"
  end

  def validate_session
    # Restore Warden/Devise from session backup when cookie was sent but Warden state was lost
    # (e.g. after redirect from signup → MFA setup, or Discord callback → verify)
    if !user_signed_in? && session[:user_id].present?
      recovered = User.find_by(id: session[:user_id])
      if recovered.present?
        sign_in(recovered, event: :authentication)
        Rails.logger.info("[Session] Restored user #{recovered.id} from session[:user_id] in validate_session")
      end
    end

    # Clear stale sessions where user_signed_in? is true but current_user is nil or invalid
    if user_signed_in?
      begin
        # Try to access current_user - if it raises an error or is nil, session is stale
        user = current_user
        unless user.present?
          # Try to recover from session[:user_id] if available
          if session[:user_id].present?
            recovered_user = User.find_by(id: session[:user_id])
            if recovered_user.present?
              # Restore session from backup
              session[:mfa_verified] = true if session[:mfa_verified]
              session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
              session.save if session.respond_to?(:save)
              return true
            end
          end
          Rails.logger.warn("Stale session detected: user_signed_in? is true but current_user is nil")
          reset_session
          flash.clear
          if json_api_request?
            return render_json_auth_error("controllers.application.session.expired")
          end
          redirect_to login_path, alert: t('controllers.application.session.expired')
          return false
        end

        # Additional check: verify the user still exists in the database
        unless User.exists?(user.id)
          Rails.logger.warn("Stale session detected: user #{user.id} no longer exists")
          reset_session
          flash.clear
          if json_api_request?
            return render_json_auth_error("controllers.application.session.invalid")
          end
          redirect_to login_path, alert: t('controllers.application.session.invalid')
          return false
        end

        # Ensure session backup is set
        session[:user_id] = user.id
        session.save if session.respond_to?(:save)
      rescue => e
        Rails.logger.error("Error validating session: #{e.message}")
        Rails.logger.error e.backtrace.first(5).join("\n")
        # Try to recover from session[:user_id] if available
        if session[:user_id].present?
          recovered_user = User.find_by(id: session[:user_id])
          if recovered_user.present?
            session[:mfa_verified] = true if session[:mfa_verified]
            session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
            session.save if session.respond_to?(:save)
            return true
          end
        end
        reset_session
        flash.clear
        if json_api_request?
          return render_json_auth_error("controllers.application.session.invalid")
        end
        redirect_to login_path, alert: t('controllers.application.session.invalid')
        return false
      end
    end
    true
  end

  def ensure_fully_authenticated
    # CRITICAL: Ensure user is fully authenticated before accessing any protected page
    # This is a final safety check that runs after authenticate_user! and require_mfa_if_enabled

    # First check: user must be signed in with a valid current_user
    unless user_signed_in? && current_user.present?
      Rails.logger.warn("Unauthenticated access attempt to #{controller_name}##{action_name} - no valid user")
      reset_session
      flash.clear
      if json_api_request?
        return render_json_auth_error("api.v1.authentication_required")
      end
      redirect_to login_path, alert: t('controllers.application.session.sign_in_required')
      return false
    end

    # Discord auth users don't need MFA - they're verified via Discord OAuth.
    # Always refresh the timestamp so the session remains valid.
    if current_user.oauth_primary_auth?
      session[:mfa_verified]    = true
      session[:mfa_verified_at] = Time.current.to_i
      return true
    end

    # Second check: MFA auth method users must have MFA verified
    unless mfa_verified_for_session?
      if json_api_request?
        return render_json_auth_error("gear.api.mfa_required", status: :forbidden)
      end
      # If MFA is not verified, redirect to appropriate page based on user state
      if current_user.mfa_enabled? && !current_user.mfa_verified?
        # MFA is enabled but not verified - redirect to setup
        redirect_to mfa_setup_path, alert: t('controllers.application.mfa.setup_required')
        return false
      elsif current_user.mfa_enabled? && current_user.mfa_verified?
        # MFA is enabled and verified, but session verification expired - redirect to verification
        redirect_to mfa_verification_path(return_to: request.path), alert: t('controllers.application.mfa.verify_required')
        return false
      else
        # MFA not enabled - redirect to setup
        redirect_to mfa_setup_path, alert: t('controllers.application.mfa.setup_required')
        return false
      end
    end

    true
  end

  # Permission checking helpers based on Discord roles
  def user_has_discord_role?(guild, role_id)
    return false unless current_user
    return false if role_id.blank?

    # First check if user's assigned role in web UI matches (guild_member.discord_role_id)
    # This works even if Discord isn't connected - role IDs are stored from synced Discord roles
    guild_member = guild.guild_members.find_by(user: current_user, status: :active)
    if guild_member&.discord_role_id == role_id
      return true
    end

    # Then check Discord API for actual Discord server roles (only if Discord is connected)
    return false unless guild.guild_discord_setting&.connected?
    return false unless current_user.user_discord_connection&.discord_user_id.present?

    discord_guild_id = guild.guild_discord_setting.discord_guild_id
    discord_user_id = current_user.user_discord_connection.discord_user_id

    begin
      discord_service = DiscordService.new
      member = discord_service.get_guild_member(discord_guild_id, discord_user_id)
      return false unless member
      member["roles"]&.include?(role_id) || false
    rescue => e
      Rails.logger.error "Failed to check Discord role: #{e.message}"
      false
    end
  end

  def can_manage_roles?(guild)
    return true if guild.owner_id == current_user.id
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    (guild.permission_role_1_id.present? && user_has_discord_role?(guild, guild.permission_role_1_id) && guild.role_1_can_manage_roles?) ||
    (guild.permission_role_2_id.present? && user_has_discord_role?(guild, guild.permission_role_2_id) && guild.role_2_can_manage_roles?) ||
    (guild.permission_role_3_id.present? && user_has_discord_role?(guild, guild.permission_role_3_id) && guild.role_3_can_manage_roles?) ||
    (guild.permission_role_4_id.present? && user_has_discord_role?(guild, guild.permission_role_4_id) && guild.role_4_can_manage_roles?)
  end

  def can_manage_applications?(guild)
    return true if guild.owner_id == current_user.id
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    (guild.permission_role_1_id.present? && user_has_discord_role?(guild, guild.permission_role_1_id) && guild.role_1_can_manage_applications?) ||
    (guild.permission_role_2_id.present? && user_has_discord_role?(guild, guild.permission_role_2_id) && guild.role_2_can_manage_applications?) ||
    (guild.permission_role_3_id.present? && user_has_discord_role?(guild, guild.permission_role_3_id) && guild.role_3_can_manage_applications?) ||
    (guild.permission_role_4_id.present? && user_has_discord_role?(guild, guild.permission_role_4_id) && guild.role_4_can_manage_applications?)
  end

  def can_manage_guild_settings?(guild, user = nil)
    target_user = user || current_user
    return true if guild.owner_id == target_user.id
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    # Check if target_user has the role with guild settings permission
    target_user_guild_member = guild.guild_members.find_by(user: target_user, status: :active)
    target_user_role_id = target_user_guild_member&.discord_role_id

    return false if target_user_role_id.blank?

    (guild.permission_role_1_id == target_user_role_id && guild.role_1_can_manage_guild_settings?) ||
    (guild.permission_role_2_id == target_user_role_id && guild.role_2_can_manage_guild_settings?) ||
    (guild.permission_role_3_id == target_user_role_id && guild.role_3_can_manage_guild_settings?) ||
    (guild.permission_role_4_id == target_user_role_id && guild.role_4_can_manage_guild_settings?)
  end

  def can_kick_members?(guild)
    return true if guild.owner_id == current_user.id
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    (guild.permission_role_1_id.present? && user_has_discord_role?(guild, guild.permission_role_1_id) && guild.role_1_can_kick_members?) ||
    (guild.permission_role_2_id.present? && user_has_discord_role?(guild, guild.permission_role_2_id) && guild.role_2_can_kick_members?) ||
    (guild.permission_role_3_id.present? && user_has_discord_role?(guild, guild.permission_role_3_id) && guild.role_3_can_kick_members?) ||
    (guild.permission_role_4_id.present? && user_has_discord_role?(guild, guild.permission_role_4_id) && guild.role_4_can_kick_members?)
  end

  def can_manage_warnings?(guild, user = nil)
    target_user = user || current_user
    return true if guild.owner_id == target_user.id

    target_member = guild.guild_members.find_by(user: target_user, status: :active)
    return true if target_member&.admin?
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    target_role_id = target_member&.discord_role_id
    return false if target_role_id.blank?

    (guild.permission_role_1_id == target_role_id && guild.role_1_can_manage_warnings?) ||
      (guild.permission_role_2_id == target_role_id && guild.role_2_can_manage_warnings?) ||
      (guild.permission_role_3_id == target_role_id && guild.role_3_can_manage_warnings?) ||
      (guild.permission_role_4_id == target_role_id && guild.role_4_can_manage_warnings?)
  end

  def can_manage_documents?(guild)
    return true if guild.owner_id == current_user.id

    # Check if user is admin (role: :admin)
    member = guild.guild_members.find_by(user: current_user, status: :active)
    return true if member&.admin? || member&.owner?

    # Check custom permission via Discord role
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    (guild.permission_role_1_id.present? && user_has_discord_role?(guild, guild.permission_role_1_id) && guild.role_1_can_manage_documents?) ||
    (guild.permission_role_2_id.present? && user_has_discord_role?(guild, guild.permission_role_2_id) && guild.role_2_can_manage_documents?) ||
    (guild.permission_role_3_id.present? && user_has_discord_role?(guild, guild.permission_role_3_id) && guild.role_3_can_manage_documents?) ||
    (guild.permission_role_4_id.present? && user_has_discord_role?(guild, guild.permission_role_4_id) && guild.role_4_can_manage_documents?)
  end

  def can_manage_files?(guild)
    return true if guild.owner_id == current_user.id

    # Check if user is admin (role: :admin)
    member = guild.guild_members.find_by(user: current_user, status: :active)
    return true if member&.admin? || member&.owner?

    # Check custom permission via Discord role
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    (guild.permission_role_1_id.present? && user_has_discord_role?(guild, guild.permission_role_1_id) && guild.role_1_can_manage_files?) ||
    (guild.permission_role_2_id.present? && user_has_discord_role?(guild, guild.permission_role_2_id) && guild.role_2_can_manage_files?) ||
    (guild.permission_role_3_id.present? && user_has_discord_role?(guild, guild.permission_role_3_id) && guild.role_3_can_manage_files?) ||
    (guild.permission_role_4_id.present? && user_has_discord_role?(guild, guild.permission_role_4_id) && guild.role_4_can_manage_files?)
  end

  def can_manage_alliance?(guild, user = nil)
    can_invite_alliance_guilds?(guild, user) || can_kick_alliance_guilds?(guild, user)
  end

  def can_invite_alliance_guilds?(guild, user = nil)
    target_user = user || current_user
    return true if guild.owner_id == target_user.id
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    target_member  = guild.guild_members.find_by(user: target_user, status: :active)
    target_role_id = target_member&.discord_role_id
    return false if target_role_id.blank?

    (guild.permission_role_1_id == target_role_id && (guild.role_1_can_invite_alliance_guilds? || guild.role_1_can_manage_alliance?)) ||
    (guild.permission_role_2_id == target_role_id && (guild.role_2_can_invite_alliance_guilds? || guild.role_2_can_manage_alliance?)) ||
    (guild.permission_role_3_id == target_role_id && (guild.role_3_can_invite_alliance_guilds? || guild.role_3_can_manage_alliance?)) ||
    (guild.permission_role_4_id == target_role_id && (guild.role_4_can_invite_alliance_guilds? || guild.role_4_can_manage_alliance?))
  end

  def can_kick_alliance_guilds?(guild, user = nil)
    target_user = user || current_user
    return true if guild.owner_id == target_user.id
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    target_member  = guild.guild_members.find_by(user: target_user, status: :active)
    target_role_id = target_member&.discord_role_id
    return false if target_role_id.blank?

    (guild.permission_role_1_id == target_role_id && (guild.role_1_can_kick_alliance_guilds? || guild.role_1_can_manage_alliance?)) ||
      (guild.permission_role_2_id == target_role_id && (guild.role_2_can_kick_alliance_guilds? || guild.role_2_can_manage_alliance?)) ||
      (guild.permission_role_3_id == target_role_id && (guild.role_3_can_kick_alliance_guilds? || guild.role_3_can_manage_alliance?)) ||
      (guild.permission_role_4_id == target_role_id && (guild.role_4_can_kick_alliance_guilds? || guild.role_4_can_manage_alliance?))
  end

  def can_manage_tags?(guild, user = nil)
    target_user = user || current_user
    return true if guild.owner_id == target_user.id
    return false unless guild.permission_role_1_id.present? || guild.permission_role_2_id.present? || guild.permission_role_3_id.present? || guild.permission_role_4_id.present?

    target_member  = guild.guild_members.find_by(user: target_user, status: :active)
    target_role_id = target_member&.discord_role_id
    return false if target_role_id.blank?

    (guild.permission_role_1_id == target_role_id && guild.role_1_can_manage_tags?) ||
      (guild.permission_role_2_id == target_role_id && guild.role_2_can_manage_tags?) ||
      (guild.permission_role_3_id == target_role_id && guild.role_3_can_manage_tags?) ||
      (guild.permission_role_4_id == target_role_id && guild.role_4_can_manage_tags?)
  end

  def can_manage_events?(guild, user = nil)
    role_permission_enabled_for?(guild, user, :can_manage_events)
  end

  def can_manage_polls?(guild, user = nil)
    role_permission_enabled_for?(guild, user, :can_manage_polls)
  end

  def can_manage_loot_rolls?(guild, user = nil)
    role_permission_enabled_for?(guild, user, :can_manage_loot_rolls)
  end

  def can_manage_discord_channels?(guild, user = nil)
    role_permission_enabled_for?(guild, user, :can_manage_discord_channels)
  end

  def can_view_activity_feed?(guild, user = nil)
    role_permission_enabled_for?(guild, user, :can_view_activity_feed)
  end

  def can_export_members_csv?(guild, user = nil)
    role_permission_enabled_for?(guild, user, :can_export_members_csv)
  end

  def can_use_message_center?(guild, user = nil)
    role_permission_enabled_for?(guild, user, :can_use_message_center)
  end

  def alliance_active_owned_guilds(alliance, user = nil)
    target_user = user || current_user
    return Guild.none unless target_user && alliance

    active_guild_ids = alliance.alliance_guilds.where(status: :active).pluck(:guild_id)
    target_user.owned_guilds.where(id: active_guild_ids)
  end

  def alliance_active_member_guilds(alliance, user = nil)
    target_user = user || current_user
    return Guild.none unless target_user && alliance

    active_guild_ids = alliance.alliance_guilds.where(status: :active).pluck(:guild_id)
    Guild.joins(:guild_members)
         .where(id: active_guild_ids)
         .where(guild_members: { user_id: target_user.id, status: GuildMember.statuses[:active] })
         .distinct
  end

  def alliance_owner_in_active_guild?(alliance, user = nil)
    alliance_active_owned_guilds(alliance, user).exists?
  end

  def alliance_custom_manager_in_active_guild?(alliance, user = nil)
    target_user = user || current_user
    return false unless target_user && alliance

    alliance_active_member_guilds(alliance, target_user).any? do |guild|
      can_manage_alliance?(guild, target_user)
    end
  end

  def alliance_custom_inviter_in_active_guild?(alliance, user = nil)
    target_user = user || current_user
    return false unless target_user && alliance

    alliance_active_member_guilds(alliance, target_user).any? do |guild|
      can_invite_alliance_guilds?(guild, target_user)
    end
  end

  def alliance_custom_kicker_in_active_guild?(alliance, user = nil)
    target_user = user || current_user
    return false unless target_user && alliance

    alliance_active_member_guilds(alliance, target_user).any? do |guild|
      can_kick_alliance_guilds?(guild, target_user)
    end
  end

  def can_manage_alliance_actions?(alliance, user = nil)
    alliance_owner_in_active_guild?(alliance, user) ||
      alliance_custom_manager_in_active_guild?(alliance, user)
  end

  def can_invite_alliance_actions?(alliance, user = nil)
    alliance_owner_in_active_guild?(alliance, user) ||
      alliance_custom_inviter_in_active_guild?(alliance, user)
  end

  def can_kick_alliance_actions?(alliance, user = nil)
    alliance_owner_in_active_guild?(alliance, user) ||
      alliance_custom_kicker_in_active_guild?(alliance, user)
  end

  def protected_alliance_target?(alliance, target_user)
    return false unless alliance && target_user

    alliance_owner_in_active_guild?(alliance, target_user) ||
      alliance_custom_manager_in_active_guild?(alliance, target_user)
  end

  # Check if target_user has higher authority than current_user in a guild
  # Higher authority is determined by:
  # 1. Guild owner always has highest authority
  # 2. Users with more permissions enabled have higher authority
  def can_manage_gear_requests?(guild, user = nil)
    target_user = user || current_user
    return true if guild.owner_id == target_user.id

    role_permission_enabled_for?(guild, target_user, :can_manage_gear_requests)
  end

  def can_edit_gear_scanned_stats?(guild, user = nil)
    target_user = user || current_user
    return false unless guild && target_user
    return true if guild.owner_id == target_user.id

    role_permission_enabled_for?(guild, target_user, :can_edit_gear_scanned_stats)
  end

  def can_view_gear?(guild, user = nil)
    target_user = user || current_user
    # All guild members can view gear
    guild.members.include?(target_user)
  end

  # View or edit another member's stat snapshot (self, guild owner, or gear-request managers only).
  def can_access_member_gear_snapshot?(guild, target_user)
    return false unless guild && target_user && current_user
    return true if current_user.id == target_user.id
    return true if guild.owner_id == current_user.id

    can_manage_gear_requests?(guild)
  end

  def can_view_member_gear_stats?(guild, target_user)
    can_access_member_gear_snapshot?(guild, target_user)
  end

  # Correct OCR-extracted stat rows: guild owner, or a role with +can_edit_gear_scanned_stats+ for *other*
  # members' snapshots. The member who uploaded their own scan cannot edit their own extracted stats.
  def can_edit_member_snapshot_data?(guild, target_user)
    return false unless guild && target_user && current_user
    return false unless guild.members.include?(current_user)
    return false unless guild.members.include?(target_user)

    return true if guild.owner_id == current_user.id
    return false if current_user.id == target_user.id

    role_permission_enabled_for?(guild, current_user, :can_edit_gear_scanned_stats)
  end

  def user_has_higher_authority_than?(guild, target_user)
    return false unless current_user && target_user && guild

    # Guild owner can always modify anyone (except themselves, but that's handled elsewhere)
    return false if guild.owner_id == current_user.id

    # Target user is guild owner - they have highest authority
    return true if guild.owner_id == target_user.id

    # Get permission counts for both users
    current_user_permission_count = count_user_permissions(guild, current_user)
    target_user_permission_count = count_user_permissions(guild, target_user)

    # User with more permissions has higher authority
    target_user_permission_count > current_user_permission_count
  end

  # Count the number of permissions enabled for a user's role in a guild
  def count_user_permissions(guild, user)
    return 0 unless user && guild

    # Find which permission role the user has
    user_guild_member = guild.guild_members.find_by(user: user, status: :active)
    user_role_id = user_guild_member&.discord_role_id

    return 0 if user_role_id.blank?

    # Count permissions for the user's role
    permission_count = 0

    if guild.permission_role_1_id == user_role_id
      permission_count += 1 if guild.role_1_can_manage_roles?
      permission_count += 1 if guild.role_1_can_manage_applications?
      permission_count += 1 if guild.role_1_can_manage_guild_settings?
      permission_count += 1 if guild.role_1_can_kick_members?
      permission_count += 1 if guild.role_1_can_manage_warnings?
      permission_count += 1 if guild.role_1_can_manage_tags?
      permission_count += 1 if guild.role_1_can_invite_alliance_guilds?
      permission_count += 1 if guild.role_1_can_kick_alliance_guilds?
      permission_count += 1 if guild.role_1_can_manage_events?
      permission_count += 1 if guild.role_1_can_manage_polls?
      permission_count += 1 if guild.role_1_can_manage_loot_rolls?
      permission_count += 1 if guild.role_1_can_manage_discord_channels?
      permission_count += 1 if guild.role_1_can_view_activity_feed?
      permission_count += 1 if guild.role_1_can_export_members_csv?
      permission_count += 1 if guild.role_1_can_use_message_center?
      permission_count += 1 if guild.role_1_can_manage_gear_requests?
      permission_count += 1 if guild.role_1_can_edit_gear_scanned_stats?
    elsif guild.permission_role_2_id == user_role_id
      permission_count += 1 if guild.role_2_can_manage_roles?
      permission_count += 1 if guild.role_2_can_manage_applications?
      permission_count += 1 if guild.role_2_can_manage_guild_settings?
      permission_count += 1 if guild.role_2_can_kick_members?
      permission_count += 1 if guild.role_2_can_manage_warnings?
      permission_count += 1 if guild.role_2_can_manage_tags?
      permission_count += 1 if guild.role_2_can_invite_alliance_guilds?
      permission_count += 1 if guild.role_2_can_kick_alliance_guilds?
      permission_count += 1 if guild.role_2_can_manage_events?
      permission_count += 1 if guild.role_2_can_manage_polls?
      permission_count += 1 if guild.role_2_can_manage_loot_rolls?
      permission_count += 1 if guild.role_2_can_manage_discord_channels?
      permission_count += 1 if guild.role_2_can_view_activity_feed?
      permission_count += 1 if guild.role_2_can_export_members_csv?
      permission_count += 1 if guild.role_2_can_use_message_center?
      permission_count += 1 if guild.role_2_can_manage_gear_requests?
      permission_count += 1 if guild.role_2_can_edit_gear_scanned_stats?
    elsif guild.permission_role_3_id == user_role_id
      permission_count += 1 if guild.role_3_can_manage_roles?
      permission_count += 1 if guild.role_3_can_manage_applications?
      permission_count += 1 if guild.role_3_can_manage_guild_settings?
      permission_count += 1 if guild.role_3_can_kick_members?
      permission_count += 1 if guild.role_3_can_manage_warnings?
      permission_count += 1 if guild.role_3_can_manage_tags?
      permission_count += 1 if guild.role_3_can_invite_alliance_guilds?
      permission_count += 1 if guild.role_3_can_kick_alliance_guilds?
      permission_count += 1 if guild.role_3_can_manage_events?
      permission_count += 1 if guild.role_3_can_manage_polls?
      permission_count += 1 if guild.role_3_can_manage_loot_rolls?
      permission_count += 1 if guild.role_3_can_manage_discord_channels?
      permission_count += 1 if guild.role_3_can_view_activity_feed?
      permission_count += 1 if guild.role_3_can_export_members_csv?
      permission_count += 1 if guild.role_3_can_use_message_center?
      permission_count += 1 if guild.role_3_can_manage_gear_requests?
      permission_count += 1 if guild.role_3_can_edit_gear_scanned_stats?
    elsif guild.permission_role_4_id == user_role_id
      permission_count += 1 if guild.role_4_can_manage_roles?
      permission_count += 1 if guild.role_4_can_manage_applications?
      permission_count += 1 if guild.role_4_can_manage_guild_settings?
      permission_count += 1 if guild.role_4_can_kick_members?
      permission_count += 1 if guild.role_4_can_manage_warnings?
      permission_count += 1 if guild.role_4_can_manage_tags?
      permission_count += 1 if guild.role_4_can_invite_alliance_guilds?
      permission_count += 1 if guild.role_4_can_kick_alliance_guilds?
      permission_count += 1 if guild.role_4_can_manage_events?
      permission_count += 1 if guild.role_4_can_manage_polls?
      permission_count += 1 if guild.role_4_can_manage_loot_rolls?
      permission_count += 1 if guild.role_4_can_manage_discord_channels?
      permission_count += 1 if guild.role_4_can_view_activity_feed?
      permission_count += 1 if guild.role_4_can_export_members_csv?
      permission_count += 1 if guild.role_4_can_use_message_center?
      permission_count += 1 if guild.role_4_can_manage_gear_requests?
      permission_count += 1 if guild.role_4_can_edit_gear_scanned_stats?
    end

    permission_count
  end

  # Admin user check - checks both admin session and environment variables
  def admin_user?
    # First check if admin session is authenticated (for /admin/* routes)
    return true if session[:admin_authenticated] == true

    # Fallback: Check environment variables for admin access (legacy support)
    return false unless current_user

    # Check environment variable for admin emails
    admin_emails = ENV.fetch("ADMIN_EMAILS", "").split(",").map(&:strip).reject(&:blank?)
    return true if admin_emails.include?(current_user.email)

    # Check environment variable for admin user IDs
    admin_user_ids = ENV.fetch("ADMIN_USER_IDS", "").split(",").map(&:strip).reject(&:blank?).map(&:to_i)
    return true if admin_user_ids.include?(current_user.id)

    false
  end

  def track_user_activity?
    UserActivity::RecordingPolicy.new(request: request, user: current_user).record?
  end

  def track_user_activity
    descriptor = UserActivity::Descriptor.build(
      controller_name: controller_name,
      action_name: action_name,
      path: request.path,
      label_override: activity_label_for_tracking
    )
    return if descriptor.skip?

    UserActivityTracker.record(
      user: current_user,
      path: request.path,
      label: descriptor.label,
      link_path: descriptor.link_path,
      record: activity_record_for_tracking
    )
  end

  # Override in controllers to set a context-aware, human-readable label (e.g. a guild name).
  # Return nil to let UserActivity::Descriptor derive a friendly page name.
  def activity_label_for_tracking
    nil
  end

  # Override in controllers to attach a polymorphic record (e.g. @guild) for the activity.
  def activity_record_for_tracking
    nil
  end

  def handle_csrf_error(exception)
    # Return JSON error for JSON requests, otherwise use default behavior
    if request.format.json? || request.headers["Content-Type"]&.include?("application/json")
      render json: {
        error: t('controllers.application.csrf.error'),
        csrf_error: true
      }, status: :unprocessable_entity
    else
      raise exception
    end
  end

  def role_permission_enabled_for?(guild, user, permission_suffix)
    target_user = user || current_user
    guild.role_permission_enabled_for?(target_user, permission_suffix)
  end

end
