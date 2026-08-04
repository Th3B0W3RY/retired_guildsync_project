# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Homepage footer links", type: :request do
  before do
    HomepageFeatureCard.find_or_create_by!(slug: "member_management") do |card|
      card.title = "Member management"
      card.description = "Manage members"
      card.icon_key = "member_management"
      card.position = 0
      card.visible = true
    end
  end

  describe "GET /" do
    it "renders working product links and dedicated footer support/legal links" do
      get root_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(href="#features"))
      expect(response.body).to include(%(href="#{pricing_path}"))
      expect(response.body).to include(%(href="#{roadmap_path}"))
      expect(response.body).to include(%(href="#{footer_support_documentation_path}"))
      expect(response.body).to include(%(href="#{footer_support_contact_path}"))
      expect(response.body).to include(%(href="#{footer_support_discord_path}"))
      expect(response.body).to include(%(href="#{privacy_policy_path}"))
      expect(response.body).to include(%(href="#{terms_of_service_path}"))
      expect(response.body).to include(%(href="#{security_page_path}"))
      expect(response.body).to include(%(href="#{disaster_recovery_page_path}"))
      expect(response.body).to include(">Discord<")
    end
  end

  describe "support redirects" do
    it "redirects documentation to the default URL" do
      get footer_support_documentation_path

      expect(response).to redirect_to(SiteSetting::DEFAULTS["homepage_footer_documentation_url"])
    end

    it "redirects contact to the configured URL" do
      SiteSetting.set("homepage_footer_contact_url", "https://support.example.test/contact")

      get footer_support_contact_path

      expect(response).to redirect_to("https://support.example.test/contact")
    end

    it "redirects discord to the configured URL" do
      SiteSetting.set("homepage_footer_discord_url", "https://discord.gg/exampleguild")

      get footer_support_discord_path

      expect(response).to redirect_to("https://discord.gg/exampleguild")
    end

    it "falls back to root with flash when documentation URL is not http(s)" do
      SiteSetting.set("homepage_footer_documentation_url", "javascript:alert(1)")

      get footer_support_documentation_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.application.invalid_external_redirect"))
    end
  end

  describe "legal pages" do
    it "renders the privacy page" do
      page = MarketingLegalPage.for_kind!("privacy")

      get privacy_policy_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(page.title)
      expect(response.body).to include(page.body.to_plain_text.squish.split.first)
    end

    it "renders the terms page" do
      page = MarketingLegalPage.for_kind!("terms")

      get terms_of_service_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(page.title)
    end

    it "renders the security page" do
      page = MarketingLegalPage.for_kind!("security")

      get security_page_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(page.title)
    end

    it "renders the disaster recovery page" do
      page = MarketingLegalPage.for_kind!("disaster_recovery")

      get disaster_recovery_page_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(ActionController::Base.helpers.strip_tags(page.title))
      expect(response.body).to include("operational resilience")
    end
  end
end
