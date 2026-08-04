# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin homepage marketing CMS (Turbo frame)", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }
  let(:frame) { Admin::DashboardController::DASHBOARD_INDEX_MAIN_FRAME }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  it "returns a matching turbo-frame body for homepage feature cards index" do
    get admin_homepage_feature_cards_path, headers: { "Turbo-Frame" => frame }

    expect(response).to have_http_status(:success)
    expect(response.body).to include(%(id="#{frame}"))
    expect(response.body).to include(I18n.t("admin.homepage_feature_cards.page_title"))
  end

  it "returns a matching turbo-frame body for landing user feedbacks index" do
    get admin_landing_user_feedbacks_path, headers: { "Turbo-Frame" => frame }

    expect(response).to have_http_status(:success)
    expect(response.body).to include(%(id="#{frame}"))
    expect(response.body).to include(I18n.t("admin.landing_user_feedbacks.page_title"))
  end
end
