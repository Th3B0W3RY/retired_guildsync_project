# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locale resolution", type: :request do
  # Each example starts with a clean cookie jar / session so Warden and sticky guest
  # session[:locale] from other examples cannot skew locale resolution.
  before { reset! }

  describe "guest (signed out)" do
    it "uses browser language when Accept-Language prefers German" do
      get root_path, headers: { "Accept-Language" => "de-DE,de;q=0.9,en;q=0.8" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/lang="de"/)
    end

    it "persists ?locale= in session for subsequent requests" do
      get root_path, params: { locale: "de" }
      expect(response).to have_http_status(:ok)
      get root_path
      expect(response.body).to match(/lang="de"/)
    end
  end

  describe "guest Accept-Language zh (isolated session)" do
    it "renders login page in Chinese when Accept-Language prefers zh (zh.common under zh tree)" do
      get login_path(email_login: 1), headers: { "Accept-Language" => "zh-CN,zh;q=0.9,en;q=0.8" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/lang="zh"/)
      expect(response.body).to include("邮箱")
      expect(response.body).to include("密码")
      expect(response.body).to include("创建账户")
      expect(response.body).to include("忘记密码")
    end

    it "re-renders login in Chinese after failed password sign-in" do
      post sign_in_path,
           params: { user: { email: "not-a-user-#{SecureRandom.hex(4)}@example.com", password: "wrong-pass" } },
           headers: { "Accept-Language" => "zh-CN,zh;q=0.9,en;q=0.8" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to match(/lang="zh"/)
      expect(response.body).to include("邮箱")
      expect(response.body).to include("密码")
    end

    it "renders login in Japanese when Accept-Language prefers ja (ja.common under locale tree)" do
      get login_path(email_login: 1), headers: { "Accept-Language" => "ja-JP,ja;q=0.9,en;q=0.8" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/lang="ja"/)
      expect(response.body).to include("メールアドレス")
      expect(response.body).to include("パスワード")
      expect(response.body).to include("サインイン")
    end
  end

  describe "signed-in user with no preferred_locale" do
    let(:user) { create(:user, :discord_auth, preferred_locale: nil) }

    before { sign_in user }

    it "uses English in <html lang> despite German Accept-Language" do
      get dashboard_path, headers: { "Accept-Language" => "de-DE,de;q=0.9,en-US;q=0.8" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/lang="en"/)
    end

    it "still honors explicit ?locale=de" do
      get dashboard_path, params: { locale: "de" }, headers: { "Accept-Language" => "en-US,en;q=0.9" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/lang="de"/)
    end

    it "uses saved preferred_locale over Accept-Language" do
      user.update!(preferred_locale: "de")
      get dashboard_path, headers: { "Accept-Language" => "en-US,en;q=0.9" }
      expect(response.body).to match(/lang="de"/)
    end
  end

  describe "PATCH /settings/locale" do
    let(:user) { create(:user, :discord_auth, preferred_locale: nil) }

    before { sign_in user }

    it "clears sticky session locale when saving default (blank) preference" do
      get dashboard_path, params: { locale: "de" }
      patch update_locale_settings_path, params: { preferred_locale: "" }
      expect(response).to have_http_status(:redirect)
      get dashboard_path
      expect(response.body).to match(/lang="en"/)
    end
  end
end
