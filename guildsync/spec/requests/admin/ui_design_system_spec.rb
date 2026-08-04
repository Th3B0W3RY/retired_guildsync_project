# frozen_string_literal: true

require "erb"
require "rails_helper"

RSpec.describe "Admin::UiDesignSystem", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/ui-design-system" do
    it "renders the design system page" do
      get "/admin/ui-design-system"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.ui_design_system.title"))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.ui_design_system.sections.colors.title")))
      expect(response.body).to include("#0f172a")
      expect(response.body).to include("bg-theme-primary")
      expect(response.body).to include("var(--gs-gradient-brand)")
      expect(response.body).to include("bg-theme-brand-gradient")
      expect(response.body).to include(".guild-permission-checkbox-grid")
    end

    it "returns frame-only HTML for Turbo frame requests" do
      get "/admin/ui-design-system", headers: { "Turbo-Frame" => Admin::UiDesignSystemController::UI_DESIGN_SYSTEM_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::UiDesignSystemController::UI_DESIGN_SYSTEM_MAIN_FRAME}"))
      expect(response.body).not_to include(I18n.t("admin.ui_design_system.title"))
    end
  end
end
