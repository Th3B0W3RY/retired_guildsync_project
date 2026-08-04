# frozen_string_literal: true

class MicrosoftUserAuthController < OidcUserAuthBaseController
  private

  def oidc_service
    @oidc_service ||= MicrosoftUserOAuthService.new
  end

  def oauth_session_prefix
    "microsoft"
  end

  def user_uid_column
    :microsoft_uid
  end

  def auth_method_key
    :microsoft
  end

  def verify_session_route_helper
    :microsoft_verify_session_path
  end

  def callback_path
    "/auth/microsoft/callback"
  end

  def oidc_credentials_present?
    ENV["MICROSOFT_CLIENT_ID"].present? && ENV["MICROSOFT_CLIENT_SECRET"].present?
  end

  def provider_email_verified?(profile)
    profile["email"].present?
  end
end
