# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::FeatureAbusersController", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  let(:warned_user) { create(:user, username: "warneduser", email: "warned@example.com") }

  before do
    UserComplianceWarning.create!(
      user: warned_user,
      warning_type: UserComplianceWarning::WARNING_TYPE_IP_CONFLICT,
      active: true,
      message: "IP conflict",
      locked_by_policy: false
    )
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/feature-abusers" do
    it "returns success" do
      get admin_feature_abusers_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(warned_user.username)
      expect(response.body).to include(I18n.t("admin.feature_abusers.title"))
      expect(response.body).to include(I18n.t("admin.feature_abusers.col_email"))
    end

    it "filters by username search" do
      get admin_feature_abusers_path, params: { q: "warneduser" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(warned_user.email)
    end

    it "filters by user id" do
      get admin_feature_abusers_path, params: { q: warned_user.id.to_s }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(warned_user.username)
    end

    it "returns frame-only HTML when Turbo-Frame targets results" do
      get admin_feature_abusers_path,
        params: { q: "warneduser" },
        headers: { "Turbo-Frame" => Admin::FeatureAbusersController::FEATURE_ABUSERS_RESULTS_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::FeatureAbusersController::FEATURE_ABUSERS_RESULTS_FRAME}"))
      expect(response.body).to include(warned_user.email)
      expect(response.body).not_to include(I18n.t("admin.feature_abusers.title"))
    end

    it "renders Portuguese feature abusers copy when locale is pt" do
      get admin_feature_abusers_path(locale: :pt)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.feature_abusers.intro", locale: :pt))
      expect(response.body).to include(I18n.t("admin.feature_abusers.search", locale: :pt))
    end

    it "renders Italian feature abusers copy when locale is it" do
      get admin_feature_abusers_path(locale: :it)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.feature_abusers.intro", locale: :it))
      expect(response.body).to include(I18n.t("admin.feature_abusers.search", locale: :it))
    end
  end

  context "when admin session is cleared" do
    before { delete admin_logout_path }

    it "redirects to admin login" do
      get admin_feature_abusers_path
      expect(response).to redirect_to(admin_login_path)
    end
  end

  describe "POST /admin/feature-abusers/:user_id/unlock" do
    before { warned_user.update_columns(locked_at: Time.current) }

    it "clears lock and deactivates IP warnings" do
      post admin_feature_abuser_unlock_path(user_id: warned_user.id)
      expect(response).to redirect_to(admin_feature_abusers_path)
      expect(flash[:notice]).to eq(I18n.t("admin.feature_abusers.flash.unlocked"))
      warned_user.reload
      expect(warned_user.locked_at).to be_nil
      expect(
        UserComplianceWarning.where(
          user_id: warned_user.id,
          warning_type: UserComplianceWarning::WARNING_TYPE_IP_CONFLICT
        ).where(active: true)
      ).to be_empty
    end

    it "returns turbo-stream row replace and flash" do
      post admin_feature_abuser_unlock_path(user_id: warned_user.id), headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="replace"', "admin_feature_abuser_row_#{warned_user.id}")
      expect(response.body).to include(I18n.t("admin.feature_abusers.flash.unlocked"))
      warned_user.reload
      expect(warned_user.locked_at).to be_nil
    end
  end

  describe "POST /admin/feature-abusers/:user_id/lock" do
    it "locks account and ensures IP warning row" do
      target = create(:user, username: "lockme", email: "lockme@example.com")
      post admin_feature_abuser_lock_path(user_id: target.id)
      expect(response).to redirect_to(admin_feature_abusers_path)
      expect(flash[:notice]).to eq(I18n.t("admin.feature_abusers.flash.locked"))
      target.reload
      expect(target.locked_at).to be_present
      expect(
        UserComplianceWarning.where(
          user_id: target.id,
          warning_type: UserComplianceWarning::WARNING_TYPE_IP_CONFLICT,
          active: true
        )
      ).to exist
    end

    it "returns turbo-stream row replace and flash" do
      post admin_feature_abuser_lock_path(user_id: warned_user.id), headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="replace"', "admin_feature_abuser_row_#{warned_user.id}")
      expect(response.body).to include(I18n.t("admin.feature_abusers.flash.locked"))
      warned_user.reload
      expect(warned_user.locked_at).to be_present
    end
  end
end
