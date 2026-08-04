# frozen_string_literal: true

module Discord
  # Decides the OAuth `prompt` parameter for the Discord authorize redirect so returning
  # users are not shown the authorize screen again when the browser already has an active
  # Discord session and previously granted the app. Returns the string "none" (silent
  # authorize) or nil (default Discord behavior — consent only on first auth / scope change).
  #
  # Discord-only: this object governs the Discord authorize URL exclusively. Google,
  # Microsoft (OIDC), and MFA flows do not use it. It never sends prompt=consent.
  #
  # The caller pairs a "none" result with a one-shot session flag so the callback can fall
  # back to a single interactive authorize if Discord reports interaction is required.
  class OAuthStartPrompt
    SILENT = "none"

    # @param silent_reauth [Boolean] app-triggered re-auth (GET /auth/discord?silent=1)
    # @param oauth_from [String, nil] "login" or "signup"
    # @param link_only [Boolean] signed-in user linking Discord to an existing account
    # @param seen_before [Boolean] signed discord_seen_before cookie present (completed OAuth before)
    # @param has_discord_uid [Boolean] signed discord_uid cookie present (known Discord identity)
    # @param cookie_silent_attempted [Boolean] cookie silent-login was tried but did not sign the user in
    def initialize(silent_reauth:, oauth_from:, link_only:, seen_before:,
                   has_discord_uid:, cookie_silent_attempted:)
      @silent_reauth = silent_reauth
      @oauth_from = oauth_from.to_s
      @link_only = link_only
      @seen_before = seen_before
      @has_discord_uid = has_discord_uid
      @cookie_silent_attempted = cookie_silent_attempted
    end

    # @return [String, nil] "none" for a silent authorize, or nil for default behavior.
    def call
      return SILENT if @silent_reauth

      # Linking Discord to a signed-in account is an explicit, deliberate action — keep
      # Discord's default behavior (consent shown only when actually needed for new scopes).
      return nil if @link_only

      return SILENT if returning_user?

      nil
    end

    private

    # A user we have positive evidence of having authorized the app before in this browser,
    # or whose Discord identity we already know. First-time signup (no such evidence) is the
    # one case we leave to Discord's default so a genuine consent can appear once.
    def returning_user?
      @seen_before || @has_discord_uid || @cookie_silent_attempted
    end
  end
end
