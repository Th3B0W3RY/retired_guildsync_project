# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include AdminAuditLogging
    
    # Skip all normal authentication - admin has separate auth
    skip_before_action :authenticate_user!
    skip_before_action :require_mfa_if_enabled
    skip_before_action :ensure_fully_authenticated
    skip_before_action :check_credentials_setup_required
    skip_before_action :validate_session
    
    before_action :require_admin
    
    layout 'application'
    
    private
    
    def require_admin
      unless admin_authenticated?
        redirect_to admin_login_path, alert: I18n.t("admin.base.require_login")
      end
    end
    
    def admin_authenticated?
      session[:admin_authenticated] == true
    end
    
    def current_admin_email
      session[:admin_email] || ENV["ADMIN_EMAIL"] || "unknown"
    end
  end
end

