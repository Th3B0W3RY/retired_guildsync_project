module Discord
  # Custom error classes for Discord token management
  module Errors
    class TokenExpiredError < StandardError; end
    class TokenRevokedError < StandardError; end
  end
  
  # Keep backwards compatible aliases
  DiscordTokenExpiredError = Errors::TokenExpiredError
  DiscordTokenRevokedError = Errors::TokenRevokedError
end

