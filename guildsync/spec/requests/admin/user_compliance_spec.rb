# frozen_string_literal: true

require "erb"
require 'rails_helper'

RSpec.describe "Admin::UserCompliance", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }
  let(:user) { create(:user, email: "user@test.com", mfa_enabled: true, otp_secret: "secret123") }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "POST /admin/user_compliance/force_logout/:user_id" do
    let!(:active_session) do
      LoginHistory.create!(
        user: user,
        login_at: 1.hour.ago,
        ip_address: "127.0.0.1"
      )
    end

    it "logs out user from all sessions" do
      expect(active_session.active?).to be true
      post force_logout_admin_user_compliance_index_path(user_id: user.id)
      expect(response).to redirect_to(admin_user_path(user))
      expect(flash[:notice]).to eq(I18n.t("admin.user_compliance.flash.force_logout"))
      active_session.reload
      expect(active_session.active?).to be false
      expect(active_session.logout_at).to be_present
    end

    it "creates audit log entry" do
      expect {
        post force_logout_admin_user_compliance_index_path(user_id: user.id)
      }.to change(AdminAuditLog, :count).by(1)
    end

    it "returns turbo-stream flash update" do
      post force_logout_admin_user_compliance_index_path(user_id: user.id),
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="update"', "admin_user_show_flash")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.user_compliance.flash.force_logout"))
      )
    end
  end

  describe "POST /admin/user_compliance/reset_mfa/:user_id" do
    it "resets MFA for user" do
      expect(user.mfa_enabled?).to be true
      expect(user.otp_secret).to be_present
      post reset_mfa_admin_user_compliance_index_path(user_id: user.id)
      expect(response).to redirect_to(admin_user_path(user))
      user.reload
      expect(user.mfa_enabled?).to be false
      expect(user.otp_secret).to be_nil
    end

    it "returns turbo-stream flash update" do
      post reset_mfa_admin_user_compliance_index_path(user_id: user.id),
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="update"', "admin_user_show_flash")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.user_compliance.flash.reset_mfa"))
      )
    end
  end

  describe "POST /admin/user_compliance/reset_email/:user_id" do
    it "updates user email" do
      new_email = "newemail@test.com"
      post reset_email_admin_user_compliance_index_path(user_id: user.id), params: { new_email: new_email }
      expect(response).to redirect_to(admin_user_path(user))
      user.reload
      expect(user.email).to eq(new_email)
    end

    it "returns turbo-stream panel refresh and updated email target" do
      new_email = "streamed@test.com"
      post reset_email_admin_user_compliance_index_path(user_id: user.id),
        params: { new_email: new_email },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"', "admin_user_compliance_panel")
      expect(response.body).to include('action="replace"', "admin_user_show_email")
      expect(response.body).to include(ERB::Util.html_escape(new_email))
      user.reload
      expect(user.email).to eq(new_email)
    end
  end

  describe "POST /admin/user_compliance/disable_account/:user_id" do
    it "disables user account" do
      expect(user.locked_at).to be_nil
      post disable_account_admin_user_compliance_index_path(user_id: user.id)
      expect(response).to redirect_to(admin_user_path(user))
      user.reload
      expect(user.locked_at).to be_present
    end

    it "returns turbo-stream panel refresh with enable action" do
      post disable_account_admin_user_compliance_index_path(user_id: user.id),
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"', "admin_user_compliance_panel")
      expect(response.body).to include(I18n.t("admin.users.show.enable_account"))
    end
  end

  describe "POST /admin/user_compliance/enable_account/:user_id" do
    before do
      user.update!(locked_at: 1.hour.ago)
    end

    it "enables user account" do
      expect(user.locked_at).to be_present
      post enable_account_admin_user_compliance_index_path(user_id: user.id)
      expect(response).to redirect_to(admin_user_path(user))
      user.reload
      expect(user.locked_at).to be_nil
    end

    it "returns turbo-stream panel refresh with disable action" do
      post enable_account_admin_user_compliance_index_path(user_id: user.id),
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"', "admin_user_compliance_panel")
      expect(response.body).to include(I18n.t("admin.users.show.disable_account"))
    end
  end

  describe "GET /admin/user_compliance/login_history/:user_id" do
    let!(:login_history1) do
      LoginHistory.create!(
        user: user,
        login_at: 2.hours.ago,
        logout_at: 1.hour.ago,
        ip_address: "127.0.0.1"
      )
    end

    let!(:login_history2) do
      LoginHistory.create!(
        user: user,
        login_at: 30.minutes.ago,
        ip_address: "192.168.1.1"
      )
    end

    it "shows login history for user" do
      get login_history_admin_user_compliance_index_path(user_id: user.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(user.email)
      expect(response.body).to include(login_history1.ip_address)
      expect(response.body).to include(login_history2.ip_address)
      expect(response.body).to include(I18n.t("admin.user_compliance.login_history.page_title", email: user.email))
      expect(response.body).to include(I18n.t("admin.user_compliance.login_history.col_login_at"))
    end

    it "returns frame-only HTML when Turbo-Frame targets main" do
      get login_history_admin_user_compliance_index_path(user_id: user.id),
        headers: { "Turbo-Frame" => Admin::UserComplianceController::LOGIN_HISTORY_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::UserComplianceController::LOGIN_HISTORY_MAIN_FRAME}"))
      expect(response.body).to include(login_history1.ip_address)
      expect(response.body).to include(I18n.t("admin.user_compliance.login_history.col_login_at"))
      expect(response.body).not_to include(I18n.t("admin.user_compliance.login_history.page_title", email: user.email))
    end
  end

  describe "authentication" do
    before do
      delete "/admin/logout"
    end

    it "requires admin authentication" do
      post force_logout_admin_user_compliance_index_path(user_id: user.id)
      expect(response).to redirect_to(admin_login_path)
    end
  end
end

