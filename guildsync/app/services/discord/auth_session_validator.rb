# frozen_string_literal: true

module Discord
  # Decides whether a Discord-primary user's app session may continue based on the
  # validity of their stored Discord OAuth token. This object only inspects/refreshes
  # the persisted UserDiscordConnection; it never touches Google/Microsoft/MFA users
  # and never issues controller redirects (callers decide what to do with the result).
  class AuthSessionValidator
    Result = Struct.new(:status) do
      def reauth_required?
        status == :reauth_required
      end

      def applicable?
        status != :not_applicable
      end
    end

    def initialize(user)
      @user = user
    end

    # @return [Result] one of:
    #   :not_applicable — not a Discord-primary user, no stored connection, or a transient error
    #   :valid          — access token still valid
    #   :refreshed      — access token was expired and successfully refreshed
    #   :reauth_required — token expired/revoked and cannot be refreshed; force Discord re-auth
    def call
      return Result.new(:not_applicable) unless @user&.discord?

      connection = @user.user_discord_connection
      # No stored Discord token (legacy/edge state): leave the existing session behavior
      # untouched. This object only governs token *expiration*, not missing-token states.
      return Result.new(:not_applicable) if connection.nil?

      return Result.new(:valid) unless connection.expired?

      # Expired with no way to refresh -> the user must re-authenticate with Discord.
      return Result.new(:reauth_required) if connection.refresh_token.blank?

      connection.refresh!
      Result.new(:refreshed)
    rescue Discord::DiscordTokenExpiredError, Discord::DiscordTokenRevokedError
      Result.new(:reauth_required)
    rescue StandardError => e
      # Transient failures (network blips, Discord 5xx) must not lock users out of the app.
      Rails.logger.warn("[Discord auth] session validation skipped (non-fatal): #{e.class}: #{e.message}")
      Result.new(:not_applicable)
    end
  end
end
