# frozen_string_literal: true

class FooterSupportLinksController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :documentation, :contact, :discord ]
  skip_before_action :require_mfa_if_enabled, only: [ :documentation, :contact, :discord ]

  def documentation
    redirect_to_trusted_site_setting_url(SiteSetting.homepage_footer_documentation_url, fallback: root_path)
  end

  def contact
    redirect_to_trusted_site_setting_url(SiteSetting.homepage_footer_contact_url, fallback: root_path)
  end

  def discord
    redirect_to_trusted_site_setting_url(SiteSetting.homepage_footer_discord_url, fallback: root_path)
  end
end
