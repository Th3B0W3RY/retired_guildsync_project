# frozen_string_literal: true

class GoogleUserAuthController < OidcUserAuthBaseController
  private

  def oidc_service
    @oidc_service ||= GoogleUserOAuthService.new
  end

  def oauth_session_prefix
    "google"
  end

  def user_uid_column
    :google_uid
  end

  def auth_method_key
    :google
  end

  def verify_session_route_helper
    :google_verify_session_path
  end

  def callback_path
    "/auth/google/callback"
  end

  def oidc_credentials_present?
    ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
  end
end
