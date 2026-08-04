# frozen_string_literal: true

# Redirects members without a verified real mailbox (e.g. Discord placeholder emails)
# to Profile Settings so they can add and confirm a real address.
#
# HTML and Turbo Stream requests only. +api/v1+ is excluded on purpose: machine clients
# (JWT, integrations) still authenticate but are not steered through the browser
# profile flow until product requires a parallel API policy.
module EnsureVerifiedRealEmail
  extend ActiveSupport::Concern

  # Controllers where incomplete email users may go without a verified address.
  SKIP_CONTROLLERS = %w[
    account_creation confirmations sessions registrations passwords
    settings profiles profile_email_verifications
    mfa_setup mfa_verification profile_completion discord_user_auth
    backup_codes recoveries
  ].freeze

  included do
    before_action :ensure_verified_real_email!
  end

  private

  def ensure_verified_real_email!
    return unless user_signed_in? && current_user
    return if current_user.verified_real_email?
    return unless enforce_verified_real_email_for_request?

    return if controller_path.start_with?("admin/")
    return if controller_path.start_with?("api/")
    return if SKIP_CONTROLLERS.include?(controller_name)

    redirect_to profile_settings_path, alert: I18n.t("settings.profile.email_verification.required_notice")
  end

  def enforce_verified_real_email_for_request?
    request.format.html? || request.format.turbo_stream?
  end
end
