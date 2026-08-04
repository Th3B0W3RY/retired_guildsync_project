require "rest-client"
require "json"
require "cgi"

class DiscordUserOAuthService
  DISCORD_API_BASE = "https://discord.com/api/v10"
  DISCORD_OAUTH_BASE = "https://discord.com/api/oauth2"

  def initialize
    # Don't check env vars in initialize - check them when needed
  end

  # Get client ID, checking if it's set
  def client_id
    @client_id ||= ENV["DISCORD_CLIENT_ID"]
    unless @client_id.present?
      raise "DISCORD_CLIENT_ID environment variable is not set. Please configure it in your .env file."
    end
    @client_id
  end

  # Get client secret, checking if it's set
  def client_secret
    @client_secret ||= ENV["DISCORD_CLIENT_SECRET"]
    unless @client_secret.present?
      raise "DISCORD_CLIENT_SECRET environment variable is not set. Please configure it in your .env file."
    end
    @client_secret
  end

  # Generate Discord OAuth authorization URL with support for silent login
  # @param redirect_uri [String] The OAuth redirect URI
  # @param state [String] OAuth state parameter for CSRF protection
  # @param prompt [String, nil] OAuth prompt parameter: "none" for silent login, "consent" for explicit consent, nil for default
  # @param scope [String] OAuth scopes (default: "identify guilds" for user login)
  def authorization_url(redirect_uri, state = nil, prompt: nil, scope: "identify guilds")
    params = {
      client_id: client_id,  # Use method that checks for env var
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: scope,
      state: state
    }.compact

    # Add prompt parameter if provided (for silent login support)
    params[:prompt] = prompt if prompt.present?

    query_string = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
    "#{DISCORD_OAUTH_BASE}/authorize?#{query_string}"
  end

  # Exchange authorization code for access token
  def exchange_code_for_token(code, redirect_uri)
    normalized_redirect_uri = redirect_uri.to_s.chomp("/")

    Rails.logger.info "Exchanging Discord OAuth code for token with redirect_uri: #{normalized_redirect_uri}"

    response = RestClient.post(
      "#{DISCORD_OAUTH_BASE}/token",
      {
        client_id: client_id,  # Use method that checks for env var
        client_secret: client_secret,  # Use method that checks for env var
        grant_type: "authorization_code",
        code: code,
        redirect_uri: normalized_redirect_uri
      },
      { "Content-Type" => "application/x-www-form-urlencoded" }
    )

    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    error_body = e.response.body rescue "No response body"
    Rails.logger.error "Discord token exchange failed: #{e.response.code} - #{error_body}"
    if e.response.code == 400
      parsed_error = JSON.parse(error_body) rescue {}
      error_description = parsed_error["error_description"] || parsed_error["error"] || "Bad Request"
      raise "Discord OAuth error: #{error_description}. Please check that your redirect URI matches exactly in Discord's developer portal."
    end
    raise
  end

  # Refresh user access token using refresh token
  def refresh_token(refresh_token)
    Rails.logger.info "Refreshing Discord user token"

    response = RestClient.post(
      "#{DISCORD_OAUTH_BASE}/token",
      {
        client_id: client_id,
        client_secret: client_secret,
        grant_type: "refresh_token",
        refresh_token: refresh_token
      },
      { "Content-Type" => "application/x-www-form-urlencoded" }
    )

    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    error_body = e.response.body rescue "No response body"
    Rails.logger.error "Discord token refresh failed: #{e.response.code} - #{error_body}"
    raise
  end

  # Get Discord user info using access token or UserDiscordConnection
  def get_user_info(access_token = nil, user_discord_connection: nil)
    # Use persisted connection if provided, otherwise use access_token
    token = if user_discord_connection
      # Get valid token (refresh if needed)
      user_discord_connection.valid_access_token
    else
      access_token
    end

    unless token
      raise "No valid Discord access token available"
    end

    response = RestClient.get(
      "#{DISCORD_API_BASE}/users/@me",
      {
        "Authorization" => "Bearer #{token}",
        "Content-Type" => "application/json"
      }
    )

    JSON.parse(response.body)
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "Failed to get Discord user info: #{e.response.code} - #{e.response.body}"

    # If token expired and we have a connection, try to refresh
    if e.response.code == 401 && user_discord_connection && user_discord_connection.refresh_token.present?
      begin
        user_discord_connection.refresh!
        # Retry with new token
        return get_user_info(nil, user_discord_connection: user_discord_connection)
      rescue => refresh_error
        Rails.logger.error "Failed to refresh token: #{refresh_error.message}"
        raise "Failed to retrieve Discord user information: Token expired and refresh failed"
      end
    end

    raise "Failed to retrieve Discord user information: #{e.response.body}"
  end

  # Revoke OAuth token at Discord (invalidates the authorization; user must re-authorize to connect again).
  # Call this only on explicit "Disconnect Discord", not on logout.
  # @param token [String] access_token or refresh_token to revoke
  # @param token_type_hint [String] "access_token" or "refresh_token"
  def revoke_token(token, token_type_hint: "refresh_token")
    return if token.blank?

    RestClient.post(
      "#{DISCORD_OAUTH_BASE}/token/revoke",
      {
        client_id: client_id,
        client_secret: client_secret,
        token: token,
        token_type_hint: token_type_hint
      },
      { "Content-Type" => "application/x-www-form-urlencoded" }
    )
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.warn "Discord token revoke failed (non-fatal): #{e.response.code} - #{e.response.body}"
    # Don't raise; disconnect should still succeed (we'll remove local data anyway)
  end

  # Get user avatar URL
  def avatar_url(user_id, avatar_hash)
    return nil unless avatar_hash.present?
    "https://cdn.discordapp.com/avatars/#{user_id}/#{avatar_hash}.png"
  end
end
