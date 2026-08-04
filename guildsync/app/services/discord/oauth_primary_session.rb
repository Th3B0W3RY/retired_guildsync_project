# frozen_string_literal: true

module Discord
  # Applies the Devise/Warden + MFA session contract for a user who proved identity via
  # Discord OAuth (a fresh callback or a successful stored-token refresh). Mirrors
  # OidcOAuthPrimarySession so password, Discord, and OIDC sign-ins persist sessions the
  # same way. Discord-only; does not touch Google/Microsoft/MFA-primary flows.
  class OAuthPrimarySession
    def self.apply!(controller, user)
      raise ArgumentError, "user required" if user.blank?

      # Use the same pattern as password logins so Devise/Warden definitely persists the
      # session before we redirect.
      controller.sign_in(user, event: :authentication)

      session = controller.session
      warden = controller.warden

      # Backup: store user id in session so validate_session can recover it.
      session[:user_id] = user.id

      # Discord OAuth (or a successful token refresh) proves identity for this session.
      # MFA-primary users who linked Discord must still skip the TOTP step here — otherwise
      # verify_session sees mfa_verified_for_session? false and sends them back to login.
      session[:mfa_verified]    = true
      session[:mfa_verified_at] = Time.current.to_i
      session[:just_logged_in]  = true
      Rails.logger.info "User #{user.id} signed in via Discord — session MFA gate satisfied"

      # Force session to be written before redirect.
      if session.respond_to?(:save)
        session.save
      elsif session.respond_to?(:commit)
        session.commit
      end

      # Ensure Warden knows about the signed-in user (for authenticate_user!).
      warden.set_user(user, scope: :user) unless warden.user(scope: :user) == user
    end
  end
end
