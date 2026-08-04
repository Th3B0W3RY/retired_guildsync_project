# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::BetaFeaturesController", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  let(:target) { create(:user, username: "betatest", email: "beta@example.com", beta_features_enabled: false) }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/beta-features" do
    it "returns success" do
      get admin_beta_features_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.beta_features.title"))
    end

    it "lists users including search match" do
      target
      get admin_beta_features_path, params: { q: "betatest" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(target.email)
    end

    it "filters by user id" do
      target
      get admin_beta_features_path, params: { q: target.id.to_s }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(target.username)
    end

    it "returns frame-only HTML when Turbo-Frame targets results" do
      target
      get admin_beta_features_path,
        params: { q: "betatest" },
        headers: { "Turbo-Frame" => Admin::BetaFeaturesController::BETA_FEATURES_RESULTS_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::BetaFeaturesController::BETA_FEATURES_RESULTS_FRAME}"))
      expect(response.body).to include(target.email)
      expect(response.body).not_to include(I18n.t("admin.beta_features.title"))
    end
  end

  describe "POST /admin/beta-features/:user_id/enable" do
    it "sets beta_features_enabled" do
      post admin_beta_feature_enable_path(user_id: target.id)
      expect(response).to redirect_to(admin_beta_features_path)
      expect(target.reload.beta_features_enabled).to be true
    end

    it "returns turbo-stream row replace and flash" do
      post admin_beta_feature_enable_path(user_id: target.id), headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(target.reload.beta_features_enabled).to be true
      expect(response.body).to include('action="replace"', "admin_beta_feature_row_#{target.id}")
      expect(response.body).to include(I18n.t("admin.beta_features.enabled_notice"))
      expect(response.body).to include(I18n.t("admin.beta_features.enabled_yes"))
    end
  end

  describe "POST /admin/beta-features/:user_id/disable" do
    it "clears beta_features_enabled" do
      target.update!(beta_features_enabled: true)
      post admin_beta_feature_disable_path(user_id: target.id)
      expect(response).to redirect_to(admin_beta_features_path)
      expect(target.reload.beta_features_enabled).to be false
    end

    it "returns turbo-stream row replace and flash" do
      target.update!(beta_features_enabled: true)
      post admin_beta_feature_disable_path(user_id: target.id), headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(target.reload.beta_features_enabled).to be false
      expect(response.body).to include('action="replace"', "admin_beta_feature_row_#{target.id}")
      expect(response.body).to include(I18n.t("admin.beta_features.disabled_notice"))
      expect(response.body).to include(I18n.t("admin.beta_features.enabled_no"))
    end
  end

  context "when admin session is cleared" do
    before { delete admin_logout_path }

    it "redirects to admin login" do
      get admin_beta_features_path
      expect(response).to redirect_to(admin_login_path)
    end
  end
end
