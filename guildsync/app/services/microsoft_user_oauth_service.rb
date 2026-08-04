# frozen_string_literal: true

require "rest-client"
require "json"
require "cgi"

class MicrosoftUserOAuthService
  CONSUMER_ACCOUNT_AUTHORITY = "https://login.microsoftonline.com/consumers"

  def authorization_uri
    "#{CONSUMER_ACCOUNT_AUTHORITY}/oauth2/v2.0/authorize"
  end

  def token_uri
    "#{CONSUMER_ACCOUNT_AUTHORITY}/oauth2/v2.0/token"
  end

  USERINFO_URI = "https://graph.microsoft.com/oidc/userinfo"

  def authorization_url(redirect_uri, state, scope: "openid email profile")
    query = {
      client_id: client_id,
      redirect_uri: redirect_uri.to_s,
      response_type: "code",
      scope: scope,
      state: state,
      response_mode: "query"
    }
    "#{authorization_uri}?#{query.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")}"
  end

  def exchange_code_for_token(code, redirect_uri)
    normalized_redirect_uri = redirect_uri.to_s.chomp("/")
    Rails.logger.info "Exchanging Microsoft OAuth code for token redirect_uri=#{normalized_redirect_uri}"

    response = RestClient.post(
      token_uri,
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
    Rails.logger.error "Microsoft token exchange failed: #{e.response.code} - #{error_body}"
    raise
  end

  def user_info(access_token)
    response = RestClient.get(
      USERINFO_URI,
      { Authorization: "Bearer #{access_token}" }
    )
    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "Microsoft userinfo failed: #{e.response.code} - #{e.response.body}"
    raise
  end

  def client_id
    @client_id ||= ENV["MICROSOFT_CLIENT_ID"]
    unless @client_id.present?
      raise "MICROSOFT_CLIENT_ID environment variable is not set. Please configure it in your .env file."
    end
    @client_id
  end

  def client_secret
    @client_secret ||= ENV["MICROSOFT_CLIENT_SECRET"]
    unless @client_secret.present?
      raise "MICROSOFT_CLIENT_SECRET environment variable is not set. Please configure it in your .env file."
    end
    @client_secret
  end
end
