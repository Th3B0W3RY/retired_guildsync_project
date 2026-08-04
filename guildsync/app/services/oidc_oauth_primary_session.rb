# frozen_string_literal: true

# Applies the same Devise/Warden + MFA session contract as DiscordUserAuthController#sign_in_user_via_discord
# for OAuth-primary providers (Gmail, Outlook). Keeps redirect-after-OAuth behavior consistent.
class OidcOAuthPrimarySession
  def self.apply!(controller, user)
    raise ArgumentError, "user required" if user.blank?

    controller.sign_in(user, event: :authentication)

    session = controller.session
    warden = controller.warden

    session[:user_id] = user.id
    session[:mfa_verified]    = true
    session[:mfa_verified_at] = Time.current.to_i
    session[:just_logged_in]  = true

    if session.respond_to?(:save)
      session.save
    elsif session.respond_to?(:commit)
      session.commit
    end

    warden.set_user(user, scope: :user) unless warden.user(scope: :user) == user
  end
end
