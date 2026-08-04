class SupportController < ApplicationController
  before_action :authenticate_user!

  def contact
    preserve_session
    redirect_to_trusted_site_setting_url(SiteSetting.release_notes_url, fallback: dashboard_path)
  end

  private

  def preserve_session
    session[:user_id] = current_user.id if current_user.present?
    session[:mfa_verified] = true if session[:mfa_verified]
    session[:mfa_verified_at] = Time.current.to_i if session[:mfa_verified_at]
    session.save if session.respond_to?(:save)
  end
end
