# frozen_string_literal: true

module Admin
  class HomepageFooterSettingsController < BaseController
    def show
      load_form_state
    end

    def update
      @support_urls = permitted_support_urls

      invalid_field = @support_urls.find { |_key, value| invalid_http_url?(value) }&.first
      if invalid_field.present?
        flash.now[:alert] = "#{human_label_for(invalid_field)} must be a valid URL."
        @marketing_legal_pages = MarketingLegalPage.with_rich_text_body.ordered
        render :show, status: :unprocessable_entity
        return
      end

      SiteSetting.set("homepage_footer_documentation_url", @support_urls[:documentation])
      SiteSetting.set("homepage_footer_contact_url", @support_urls[:contact])
      SiteSetting.set("homepage_footer_discord_url", @support_urls[:discord])

      AdminAuditLog.log_action(
        admin_email: current_admin_email,
        action: "update_homepage_footer_support_links",
        controller: "homepage_footer_settings",
        record: nil,
        changes_data: @support_urls
      )

      redirect_to admin_homepage_footer_settings_path,
                  notice: "Homepage footer support links updated."
    end

    private

    def load_form_state
      MarketingLegalPage.ensure_defaults!
      @support_urls = {
        documentation: SiteSetting.homepage_footer_documentation_url,
        contact: SiteSetting.homepage_footer_contact_url,
        discord: SiteSetting.homepage_footer_discord_url
      }
      @marketing_legal_pages = MarketingLegalPage.with_rich_text_body.ordered
    end

    def permitted_support_urls
      {
        documentation: params.dig(:homepage_footer, :documentation_url).to_s.strip,
        contact: params.dig(:homepage_footer, :contact_url).to_s.strip,
        discord: params.dig(:homepage_footer, :discord_url).to_s.strip
      }
    end

    def invalid_http_url?(value)
      Guildsync::ExternalRedirectUrl.build!(value)
      false
    rescue Guildsync::ExternalRedirectUrl::Invalid
      true
    end

    def human_label_for(field)
      {
        documentation: "Documentation URL",
        contact: "Contact URL",
        discord: "Discord URL"
      }.fetch(field)
    end
  end
end
