# frozen_string_literal: true

module Discord
  # Attempts a server-side Discord silent login from a known discord_user_id (read from the
  # signed discord_uid cookie). It locates the UserDiscordConnection and refreshes the token
  # if expired, but does NOT sign the user in or touch cookies — the caller applies the
  # session (Discord::OAuthPrimarySession) and handles cookie cleanup/redirects so the
  # controller keeps ownership of HTTP concerns. Discord-only.
  class CookieSilentSignIn
    Result = Struct.new(:status, :user) do
      def signed_in?
        status == :signed_in
      end

      # discord_uid was present but we could not complete a silent login (no connection or
      # refresh failed); the caller should clear stale cookies and fall back to OAuth.
      def fallthrough?
        status == :fallthrough
      end

      def not_applicable?
        status == :not_applicable
      end
    end

    def initialize(discord_uid)
      @discord_uid = discord_uid
    end

    def self.call(discord_uid)
      new(discord_uid).call
    end

    # @return [Result] :signed_in (with user ready to sign in), :fallthrough, or :not_applicable
    def call
      return Result.new(:not_applicable, nil) if @discord_uid.blank?

      connection = UserDiscordConnection.find_by(discord_user_id: @discord_uid)
      return Result.new(:fallthrough, nil) if connection.nil? || connection.refresh_token.blank?

      connection.refresh! if connection.expired?
      Result.new(:signed_in, connection.user)
    rescue StandardError => e
      Rails.logger.warn "[Discord auth] cookie silent login failed (non-fatal): #{e.class}: #{e.message}"
      Result.new(:fallthrough, nil)
    end
  end
end
