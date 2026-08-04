# frozen_string_literal: true

module Admin
  class SessionsController < ApplicationController
    include AdminAuditLogging

    SESSIONS_NEW_MAIN_FRAME = "admin_sessions_login_main"

    # Skip all normal authentication - admin has separate auth
    skip_before_action :authenticate_user!
    skip_before_action :require_mfa_if_enabled
    skip_before_action :ensure_fully_authenticated
    skip_before_action :check_credentials_setup_required
    skip_before_action :validate_session
    
    def new
      return redirect_to admin_root_path if admin_authenticated?
      if turbo_frame_request?
        @turbo_frame_id = request.headers["Turbo-Frame"].presence || SESSIONS_NEW_MAIN_FRAME
        return render("sessions_new_frame", layout: false)
      end
    end
    
    def create
      email = params[:email]&.strip&.downcase
      password = params[:password].to_s

      # Check ADMIN_EMAIL first (singular), then ADMIN_EMAILS (plural, comma-separated).
      # Chomp ADMIN_PASSWORD: Docker/K8s/env files often inject a trailing newline (\n or \r\n),
      # which makes secure_compare fail against the typed password (symptom: endless 422 on /admin/login).
      # We use chomp (not strip) to preserve any intentional leading/trailing spaces in the password.
      admin_email = ENV["ADMIN_EMAIL"]&.strip&.downcase
      admin_email = nil if admin_email.blank?
      admin_emails = ENV.fetch("ADMIN_EMAILS", "").split(",").map { |s| s.strip.downcase }.reject(&:blank?)
      admin_password = ENV["ADMIN_PASSWORD"].to_s.chomp
      
      # Check if email matches (either ADMIN_EMAIL or in ADMIN_EMAILS list)
      email_matches = false
      if admin_email.present? && ActiveSupport::SecurityUtils.secure_compare(email.to_s, admin_email)
        email_matches = true
      elsif admin_emails.any?
        email_matches = admin_emails.any? { |candidate| ActiveSupport::SecurityUtils.secure_compare(email.to_s, candidate) }
      end
      
      # Check if password matches
      password_matches = admin_password.present? && ActiveSupport::SecurityUtils.secure_compare(password, admin_password)
      
      # Authenticate if both match
      if email_matches && password_matches
        # Drop any Devise `:user` session first so the browser is never both a member user
        # and an admin (fixes broken main-app logout and intermittent Warden/session mismatch).
        sign_out(:user) if user_signed_in?
        reset_session
        session[:admin_authenticated] = true
        session[:admin_email] = email
        session.save if session.respond_to?(:save)
        safe_log_admin_auth_action(email: email, action: "admin_login_success")
        redirect_to admin_root_path, notice: I18n.t("admin.sessions.logged_in")
      else
        safe_log_admin_auth_action(email: email.presence || "unknown", action: "admin_login_failed")
        flash.now[:alert] = I18n.t("admin.sessions.invalid_credentials")
        render_new_with_status(:unprocessable_entity)
      end
    end
    
    def destroy
      admin_email = session[:admin_email].presence || "unknown"
      was_auth = session[:admin_authenticated]
      Rails.logger.info(
        "[Admin::Sessions] logout request_id=#{request.request_id} authenticated=#{was_auth.inspect} email=#{admin_email}"
      )
      if was_auth
        safe_log_admin_auth_action(email: admin_email, action: "admin_logout")
      end
      reset_session
      Rails.logger.info("[Admin::Sessions] logout complete request_id=#{request.request_id}")
      redirect_to admin_login_path, notice: I18n.t("admin.sessions.logged_out")
    end
    
    private
    
    def admin_authenticated?
      session[:admin_authenticated] == true
    end

    def render_new_with_status(status)
      if turbo_frame_request?
        @turbo_frame_id = request.headers["Turbo-Frame"].presence || SESSIONS_NEW_MAIN_FRAME
        render("sessions_new_frame", layout: false, status: status)
      else
        render(:new, status: status)
      end
    end

    def safe_log_admin_auth_action(email:, action:)
      AdminAuditLog.log_action(
        admin_email: email,
        action: action,
        controller: controller_name,
        request: request
      )
    rescue => e
      Rails.logger.warn("Admin auth audit log failed for #{action}: #{e.class} #{e.message}")
    end
  end
end
