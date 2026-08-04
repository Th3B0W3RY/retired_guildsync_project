# frozen_string_literal: true

module MfaHelpers
  def set_mfa_verified_in_session
    # Make a request to establish session context - must be within a request block
    get dashboard_path rescue nil
    # Set MFA verification in session after request
    session[:mfa_verified] = true
    session[:mfa_verified_at] = Time.current.to_i
    # Also set just_logged_in to false to prevent redirect loops
    session[:just_logged_in] = false
  end
end

RSpec.configure do |config|
  config.include MfaHelpers, type: :request
end

