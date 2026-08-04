module MfaVerification
  extend ActiveSupport::Concern

  included do
    # Make helper methods available in views
    helper_method :mfa_verified_for_session?
  end

  private

  # Check if user is signed in AND MFA is verified for the current session.
  # This ensures the sidebar and authenticated UI elements only show after MFA verification.
  def mfa_verified_for_session?
    return false unless user_signed_in?

    # OAuth-primary sign-in (Discord, Gmail, Outlook) is the authentication — no MFA window applies.
    return true if current_user.oauth_primary_auth?

    # MFA auth method users - MFA is mandatory
    return false unless current_user.mfa_enabled? && current_user.mfa_verified?

    # Check if MFA is verified in the current session
    return false unless session[:mfa_verified]

    # Check if verification is still valid (within 30 minutes)
    if session[:mfa_verified_at]
      verified_at = Time.at(session[:mfa_verified_at])
      return verified_at > 30.minutes.ago
    end

    false
  end
end
