# frozen_string_literal: true

require "rest-client"
require "json"
require "cgi"

class GoogleUserOAuthService
  AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth"
  TOKEN_URI = "https://oauth2.googleapis.com/token"
  USERINFO_URI = "https://openidconnect.googleapis.com/v1/userinfo"

  def authorization_url(redirect_uri, state, scope: "openid email profile")
    query = {
      client_id: client_id,
      redirect_uri: redirect_uri.to_s,
      response_type: "code",
      scope: scope,
      state: state,
      access_type: "online",
      include_granted_scopes: "true"
    }
    "#{AUTH_URI}?#{query.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")}"
  end

  def exchange_code_for_token(code, redirect_uri)
    normalized_redirect_uri = redirect_uri.to_s.chomp("/")
    Rails.logger.info "Exchanging Google OAuth code for token redirect_uri=#{normalized_redirect_uri}"

    response = RestClient.post(
      TOKEN_URI,
      {
        client_id: client_id,
        client_secret: client_secret,
        grant_type: "authorization_code",
        code: code,
        redirect_uri: normalized_redirect_uri
      },
      { "Content-Type" => "application/x-www-form-urlencoded" }
    )

    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    error_body = e.response.body rescue "No response body"
    Rails.logger.error "Google token exchange failed: #{e.response.code} - #{error_body}"
    raise
  end

  def user_info(access_token)
    response = RestClient.get(
      USERINFO_URI,
      { Authorization: "Bearer #{access_token}" }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "Google userinfo failed: #{e.response.code} - #{e.response.body}"
    raise
  end

  def client_id
    @client_id ||= ENV["GOOGLE_CLIENT_ID"]
    unless @client_id.present?
      raise "GOOGLE_CLIENT_ID environment variable is not set. Please configure it in your .env file."
    end
    @client_id
  end

  def client_secret
    @client_secret ||= ENV["GOOGLE_CLIENT_SECRET"]
    unless @client_secret.present?
      raise "GOOGLE_CLIENT_SECRET environment variable is not set. Please configure it in your .env file."
    end
    @client_secret
  end
end
