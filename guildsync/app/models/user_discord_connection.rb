class UserDiscordConnection < ApplicationRecord
  belongs_to :user

  encrypts :access_token, :refresh_token, support_unencrypted_data: true

  def expired?
    expires_at.present? && Time.current >= expires_at
  end

  def valid_access_token
    return access_token unless expired?

    refresh!
    access_token
  end

  def refresh!
    # Use DiscordUserOAuthService for user token refresh (NOT bot tokens)
    service = DiscordUserOAuthService.new
    refreshed = service.refresh_token(refresh_token)
    update!(
      access_token: refreshed["access_token"],
      refresh_token: refreshed["refresh_token"] || refresh_token,
      expires_at: Time.current + refreshed["expires_in"].to_i.seconds
    )
  rescue RestClient::ExceptionWithResponse => e
    # If refresh fails, delete the connection since access_token is NOT NULL
    # The user will need to reconnect, which will create a new record
    if e.response.code == 400 || e.response.code == 401
      # Parse error to determine if token was revoked or expired
      error_body = e.response.body rescue "{}"
      parsed_error = JSON.parse(error_body) rescue {}
      error_code = parsed_error["error"] || ""
      
      # Store error message before destroying the record
      error_message = if error_code == "invalid_grant"
        "Discord token was revoked. Please reconnect your Discord account."
      else
        "Discord token expired. Please reconnect your Discord account."
      end
      
      # Delete the connection record since we can't set access_token to nil
      destroy
      
      # Raise appropriate error after destroying the record
      if error_code == "invalid_grant"
        raise Discord::DiscordTokenRevokedError, error_message
      else
        raise Discord::DiscordTokenExpiredError, error_message
      end
    end
    raise
  end
end
