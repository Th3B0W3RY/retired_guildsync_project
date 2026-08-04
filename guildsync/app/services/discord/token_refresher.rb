require "rest-client"
require "json"

module Discord
  class TokenRefresher
    DISCORD_OAUTH_BASE = "https://discord.com/api/oauth2"

    def initialize
      @client_id = ENV["DISCORD_CLIENT_ID"]
      @client_secret = ENV["DISCORD_CLIENT_SECRET"]

      unless @client_id.present? && @client_secret.present?
        raise "DISCORD_CLIENT_ID and DISCORD_CLIENT_SECRET must be set"
      end
    end

    # Refresh access token for a UserDiscordConnection
    def refresh(user_discord_connection)
      return nil unless user_discord_connection.refresh_token.present?

      Rails.logger.info "Refreshing Discord token for user #{user_discord_connection.user_id}"

      response = RestClient.post(
        "#{DISCORD_OAUTH_BASE}/token",
        {
          client_id: @client_id,
          client_secret: @client_secret,
          grant_type: "refresh_token",
          refresh_token: user_discord_connection.refresh_token
        },
        { "Content-Type" => "application/x-www-form-urlencoded" }
      )

      token_data = JSON.parse(response.body)

      # Update the connection with new tokens
      expires_at = token_data["expires_in"] ? Time.current + token_data["expires_in"].seconds : nil

      user_discord_connection.update!(
        access_token: token_data["access_token"],
        refresh_token: token_data["refresh_token"] || user_discord_connection.refresh_token,
        expires_at: expires_at,
        scopes: token_data["scope"]
      )

      Rails.logger.info "Successfully refreshed Discord token for user #{user_discord_connection.user_id}"
      token_data
    rescue RestClient::ExceptionWithResponse => e
      error_body = e.response.body rescue "No response body"
      Rails.logger.error "Discord token refresh failed: #{e.response.code} - #{error_body}"

      # If refresh fails with invalid_grant, token was revoked
      if e.response.code == 400 || e.response.code == 401
        parsed_error = JSON.parse(error_body) rescue {}
        error_code = parsed_error["error"] || ""

        if error_code == "invalid_grant"
          # Token was revoked - delete connection since access_token is NOT NULL
          Rails.logger.warn "Discord token revoked for user #{user_discord_connection.user_id} - deleting connection"
          user_discord_connection.destroy
          raise Discord::DiscordTokenRevokedError, "Discord token was revoked. Please reconnect your Discord account."
        else
          # Other error - delete connection and raise
          Rails.logger.warn "Discord token expired for user #{user_discord_connection.user_id} - deleting connection"
          user_discord_connection.destroy
          raise Discord::DiscordTokenExpiredError, "Discord token expired. Please reconnect your Discord account."
        end
      end
      raise
    end
  end
end
