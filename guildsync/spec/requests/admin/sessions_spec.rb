# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin::Sessions", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/login" do
    it "shows the admin login page" do
      get "/admin/login"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_sessions_login_main"))
      expect(response.body).to include(I18n.t("admin.sessions.login_heading"))
      expect(response.body).to include(I18n.t("admin.sessions.email_label"))
      expect(response.body).to include(I18n.t("admin.sessions.password_label"))
      expect(response.body).to include(I18n.t("admin.sessions.submit"))
      expect(response.body).to include(I18n.t("admin.sessions.secure_notice"))
      expect(response.body).to include('data-turbo="false"')
    end

    it "renders frame-only body when Turbo-Frame requests login main" do
      get "/admin/login",
        headers: { "Turbo-Frame" => Admin::SessionsController::SESSIONS_NEW_MAIN_FRAME }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_sessions_login_main"))
      expect(response.body).to include(I18n.t("admin.sessions.login_heading"))
      expect(response.body).to include(%(action="/admin/login"))
    end


    it "renders the login payload inside arbitrary Turbo-Frame targets to avoid Content missing" do
      get "/admin/login",
        headers: { "Turbo-Frame" => Admin::DashboardController::DASHBOARD_INDEX_MAIN_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="#{Admin::DashboardController::DASHBOARD_INDEX_MAIN_FRAME}"))
      expect(response.body).to include(I18n.t("admin.sessions.login_heading"))
      expect(response.body).to include(%(action="/admin/login"))
    end

    it "does not render the member app sidebar when a member is already signed in" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user
      allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)

      get "/admin/login"
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('id="sidebar"')
      expect(response.body).to include(I18n.t("layouts.application.nav.back_to_member_dashboard"))
    end

    it "redirects to dashboard if already authenticated" do
      post "/admin/login", params: { email: admin_email, password: admin_password }
      get "/admin/login"
      expect(response).to redirect_to(admin_root_path)
    end
  end

  describe "POST /admin/login" do
    it "authenticates with correct credentials" do
      post "/admin/login", params: { email: admin_email, password: admin_password }
      expect(response).to redirect_to(admin_root_path)
      expect(session[:admin_authenticated]).to be true
    end

    it "authenticates when ADMIN_PASSWORD in ENV has a trailing newline (Docker/K8s/env-file quirk)" do
      ENV["ADMIN_PASSWORD"] = "#{admin_password}\n"
      post "/admin/login", params: { email: admin_email, password: admin_password }
      expect(response).to redirect_to(admin_root_path)
      expect(session[:admin_authenticated]).to be true
    end

    it "authenticates when ADMIN_EMAIL in ENV has trailing/leading whitespace" do
      ENV["ADMIN_EMAIL"] = "  #{admin_email.upcase}  "
      post "/admin/login", params: { email: admin_email, password: admin_password }
      expect(response).to redirect_to(admin_root_path)
      expect(session[:admin_authenticated]).to be true
    end

    it "authenticates when the email is listed in ADMIN_EMAILS and ADMIN_EMAIL is unset" do
      saved_main = ENV["ADMIN_EMAIL"]
      ENV.delete("ADMIN_EMAIL")
      ENV["ADMIN_EMAILS"] = "ops@example.com, #{admin_email.upcase} , other@example.com"

      post "/admin/login", params: { email: admin_email, password: admin_password }

      expect(response).to redirect_to(admin_root_path)
      expect(session[:admin_authenticated]).to be true
    ensure
      ENV.delete("ADMIN_EMAILS")
      ENV["ADMIN_EMAIL"] = saved_main if saved_main
    end

    it "rejects incorrect email" do
      post "/admin/login", params: { email: "wrong@test.com", password: admin_password }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(session[:admin_authenticated]).to be_nil
      expect(response.body).to include(I18n.t("admin.sessions.invalid_credentials"))
    end

    it "rejects incorrect password" do
      post "/admin/login", params: { email: admin_email, password: "wrong_password" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(session[:admin_authenticated]).to be_nil
      expect(response.body).to include(I18n.t("admin.sessions.invalid_credentials"))
    end

    it "returns the requested turbo frame on failed login to avoid content-missing swaps" do
      post "/admin/login",
        params: { email: admin_email, password: "wrong_password" },
        headers: { "Turbo-Frame" => Admin::SessionsController::SESSIONS_NEW_MAIN_FRAME }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(%(turbo-frame id="admin_sessions_login_main"))
      expect(response.body).to include(I18n.t("admin.sessions.invalid_credentials"))
    end

    it "handles case-insensitive email matching" do
      post "/admin/login", params: { email: admin_email.upcase, password: admin_password }
      expect(response).to redirect_to(admin_root_path)
      expect(session[:admin_authenticated]).to be true
    end

    it "signs out the normal Devise user and blocks dashboard access" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user

      post "/admin/login", params: { email: admin_email, password: admin_password }
      expect(response).to redirect_to(admin_root_path)
      expect(session[:admin_authenticated]).to be true

      get dashboard_path
      expect(response).to be_redirect
      # Devise may send unauthenticated users to /login or / depending on config
      expect(response.location).not_to match(%r{/dashboard})
    end

    it "does not clear the member session when admin credentials are wrong" do
      user = create(:user)
      user.update!(auth_method: "discord")
      sign_in user

      post "/admin/login", params: { email: admin_email, password: "wrong_password" }
      expect(response).to have_http_status(:unprocessable_entity)

      get dashboard_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "member sign-in clears admin console session" do
    it "removes admin_authenticated when a user signs in" do
      post "/admin/login", params: { email: admin_email, password: admin_password }
      expect(session[:admin_authenticated]).to be true

      user = create(:user)
      user.update!(auth_method: "discord")
      post "/sign_in", params: { user: { email: user.email, password: "password123" } }

      expect(session[:admin_authenticated]).to be_nil
      expect(session[:admin_email]).to be_nil
    end
  end

  describe "DELETE /admin/logout" do
    it "logs out and clears session" do
      post "/admin/login", params: { email: admin_email, password: admin_password }
      expect(session[:admin_authenticated]).to be true

      delete "/admin/logout"
      expect(response).to redirect_to(admin_login_path)
      expect(session[:admin_authenticated]).to be_nil
    end
  end

  describe "admin dashboard sign-out UI" do
    it "uses a form POST to DELETE /admin/logout (works without Turbo link hijacking)" do
      post "/admin/login", params: { email: admin_email, password: admin_password }
      get "/admin"
      expect(response).to have_http_status(:success)
      expect(response.body).to match(%r{action="/admin/logout"})
      expect(response.body).to include('name="_method"')
      expect(response.body).to include('value="delete"')
    end

    it "uses _top navigation for Admin Dashboard link on mobile variant to avoid frame-trapped visits" do
      post "/admin/login", params: { email: admin_email, password: admin_password }

      get "/admin",
        headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)
      admin_link = doc.at_css(%(a[href="#{admin_root_path}"]))
      expect(admin_link).not_to be_nil
      expect(admin_link["data-turbo-frame"]).to eq("_top")
    end
  end
end
