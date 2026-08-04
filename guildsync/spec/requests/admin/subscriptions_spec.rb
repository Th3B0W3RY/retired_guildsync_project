# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin::SubscriptionsController", type: :request do
  let(:admin_email) { "admin@test.com" }
  let(:admin_password) { "secure_password_123" }
  let(:free_plan) { create(:pricing_plan, name: "Free") }
  let(:paid_plan) { create(:pricing_plan, name: "Pro") }

  before do
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    post "/admin/login", params: { email: admin_email, password: admin_password }
  end

  after do
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
  end

  describe "GET /admin/subscriptions/paying" do
    let!(:paying_user) do
      user = create(:user, email: "paying@test.com")
      create(:subscription, user: user, pricing_plan: paid_plan, status: :active, trial_ends_at: nil, started_at: 1.month.ago)
      user
    end

    let!(:free_user) do
      user = create(:user, email: "free@test.com")
      create(:subscription, user: user, pricing_plan: free_plan, status: :active, trial_ends_at: nil, started_at: 1.month.ago)
      user
    end

    let!(:trial_user) do
      user = create(:user, email: "trial@test.com")
      create(:subscription, user: user, pricing_plan: free_plan, status: :trialing, trial_ends_at: 1.week.from_now, started_at: 1.week.ago)
      user
    end

    it "returns success" do
      get paying_users_admin_subscriptions_path
      expect(response).to have_http_status(:success)
    end

    it "renders page chrome from i18n" do
      get paying_users_admin_subscriptions_path
      expect(response.body).to include(I18n.t("admin.subscriptions.paying_users.page_title"))
      expect(response.body).to include(I18n.t("admin.subscriptions.paying_users.link_trial_users"))
    end

    it "renders German page chrome when locale is de" do
      get paying_users_admin_subscriptions_path(locale: :de)
      expect(response.body).to include(I18n.t("admin.subscriptions.paying_users.page_title", locale: :de))
    end

    it "lists paying users" do
      get paying_users_admin_subscriptions_path
      expect(response.body).to include(paying_user.email)
    end

    it "does not list free plan users" do
      get paying_users_admin_subscriptions_path
      expect(response.body).not_to include(free_user.email)
    end

    it "does not list trial users" do
      get paying_users_admin_subscriptions_path
      expect(response.body).not_to include(trial_user.email)
    end

    context "with search query" do
      it "filters users by email" do
        get paying_users_admin_subscriptions_path, params: { q: "paying" }
        expect(response.body).to include(paying_user.email)
        expect(response.body).not_to include(trial_user.email)
      end

      it "filters users by username" do
        get paying_users_admin_subscriptions_path, params: { q: paying_user.username }
        expect(response.body).to include(paying_user.email)
      end
    end

    it "returns frame-only HTML when Turbo-Frame targets paying list" do
      get paying_users_admin_subscriptions_path,
        headers: { "Turbo-Frame" => Admin::SubscriptionsController::PAYING_RESULTS_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::SubscriptionsController::PAYING_RESULTS_FRAME}"))
      expect(response.body).to include(paying_user.email)
      expect(response.body).not_to include(I18n.t("admin.subscriptions.paying_users.link_trial_users"))
    end
  end

  describe "GET /admin/subscriptions/trials" do
    let!(:trial_user) do
      user = create(:user, email: "trial@test.com")
      create(:subscription, user: user, pricing_plan: free_plan, status: :trialing, trial_ends_at: 1.week.from_now, started_at: 1.week.ago)
      user
    end

    let!(:expired_trial_user) do
      user = create(:user, email: "expired@test.com")
      # Cancel any auto-created Free plan subscription first
      user.subscriptions.where(status: [:active, :trialing]).update_all(status: :canceled, canceled_at: Time.current)
      # Create expired trial subscription
      create(:subscription, user: user, pricing_plan: free_plan, status: :trialing, trial_ends_at: 1.week.ago, started_at: 2.weeks.ago)
      user.reload
      user
    end

    let!(:paying_user) do
      user = create(:user, email: "paying@test.com")
      # Cancel any auto-created Free plan subscription first
      user.subscriptions.where(status: [:active, :trialing]).update_all(status: :canceled, canceled_at: Time.current)
      # Create paid plan subscription
      create(:subscription, user: user, pricing_plan: paid_plan, status: :active, trial_ends_at: nil, started_at: 1.month.ago)
      user.reload
      user
    end

    it "returns success" do
      get trial_users_admin_subscriptions_path
      expect(response).to have_http_status(:success)
    end

    it "renders page chrome from i18n" do
      get trial_users_admin_subscriptions_path
      expect(response.body).to include(I18n.t("admin.subscriptions.trial_users.page_title"))
      expect(response.body).to include(I18n.t("admin.subscriptions.trial_users.link_paying_users"))
    end

    it "lists active trial users" do
      get trial_users_admin_subscriptions_path
      expect(response.body).to include(trial_user.email)
    end

    it "does not list expired trial users" do
      get trial_users_admin_subscriptions_path
      expect(response.body).not_to include(expired_trial_user.email)
    end

    it "does not list paying users" do
      get trial_users_admin_subscriptions_path
      expect(response.body).not_to include(paying_user.email)
    end

    context "with search query" do
      it "filters users by email" do
        get trial_users_admin_subscriptions_path, params: { q: "trial" }
        expect(response.body).to include(trial_user.email)
        expect(response.body).not_to include(paying_user.email)
      end

      it "filters users by username" do
        get trial_users_admin_subscriptions_path, params: { q: trial_user.username }
        expect(response.body).to include(trial_user.email)
      end
    end

    it "returns frame-only HTML when Turbo-Frame targets trial list" do
      get trial_users_admin_subscriptions_path,
        headers: { "Turbo-Frame" => Admin::SubscriptionsController::TRIAL_RESULTS_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::SubscriptionsController::TRIAL_RESULTS_FRAME}"))
      expect(response.body).to include(trial_user.email)
      expect(response.body).not_to include(I18n.t("admin.subscriptions.trial_users.link_paying_users"))
    end
  end

  describe "authentication" do
    before do
      delete "/admin/logout"
    end

    it "requires admin authentication for paying users" do
      get paying_users_admin_subscriptions_path
      expect(response).to redirect_to(admin_login_path)
    end

    it "requires admin authentication for trial users" do
      get trial_users_admin_subscriptions_path
      expect(response).to redirect_to(admin_login_path)
    end
  end

  describe "GET /admin/subscriptions/paying/search" do
    let!(:paying_user) do
      user = create(:user, email: "paying@test.com", username: "payinguser")
      user.subscriptions.where(status: [:active, :trialing]).update_all(status: :canceled, canceled_at: Time.current)
      create(:subscription, user: user, pricing_plan: paid_plan, status: :active, trial_ends_at: nil, started_at: 1.month.ago)
      user.reload
      user
    end

    let!(:free_user) do
      user = create(:user, email: "free@test.com", username: "freeuser")
      user.subscriptions.where(status: [:active, :trialing]).update_all(status: :canceled, canceled_at: Time.current)
      create(:subscription, user: user, pricing_plan: free_plan, status: :active, trial_ends_at: nil, started_at: 1.month.ago)
      user.reload
      user
    end

    it "returns JSON with paying user suggestions" do
      get "/admin/subscriptions/paying/search", params: { q: "paying" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")
      
      json = JSON.parse(response.body)
      expect(json).to have_key("users")
      expect(json["users"].length).to be > 0
      expect(json["users"].first).to have_key("email")
      expect(json["users"].first).to have_key("username")
      expect(json["users"].first["status"]).to eq(I18n.t("admin.users.show.subscription_status.active"))
      expect(json["users"].first["plan"]).to eq("Pro")
    end

    it "only returns paying users" do
      get "/admin/subscriptions/paying/search", params: { q: "test" }
      json = JSON.parse(response.body)
      user_emails = json["users"].map { |u| u["email"] }
      expect(user_emails).to include(paying_user.email)
      expect(user_emails).not_to include(free_user.email)
    end

    it "returns empty array for blank query" do
      get "/admin/subscriptions/paying/search", params: { q: "" }
      json = JSON.parse(response.body)
      expect(json["users"]).to eq([])
    end
  end

  describe "GET /admin/subscriptions/trials/search" do
    let!(:trial_user) do
      user = create(:user, email: "trial@test.com", username: "trialuser")
      # Cancel any auto-created Free plan subscription first
      user.subscriptions.where(status: [:active, :trialing]).update_all(status: :canceled, canceled_at: Time.current)
      create(:subscription, user: user, pricing_plan: free_plan, status: :trialing, trial_ends_at: 1.week.from_now, started_at: 1.week.ago)
      user.reload
      user
    end

    let!(:free_user) do
      user = create(:user, email: "free@test.com", username: "freeuser")
      user.subscriptions.where(status: [:active, :trialing]).update_all(status: :canceled, canceled_at: Time.current)
      create(:subscription, user: user, pricing_plan: free_plan, status: :active, trial_ends_at: nil, started_at: 1.month.ago)
      user.reload
      user
    end

    it "returns JSON with trial user suggestions" do
      get "/admin/subscriptions/trials/search", params: { q: "trial" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")
      
      json = JSON.parse(response.body)
      expect(json).to have_key("users")
      expect(json["users"].length).to be > 0
      expect(json["users"].first).to have_key("email")
      expect(json["users"].first).to have_key("username")
      expect(json["users"].first["status"]).to eq(I18n.t("admin.users.show.subscription_status.trialing"))
      expect(json["users"].first["plan"]).to eq("Free")
    end

    it "returns both trial and free users" do
      # Use specific usernames to avoid matching users from other tests
      get "/admin/subscriptions/trials/search", params: { q: "trialuser" }
      json = JSON.parse(response.body)
      user_emails = json["users"].map { |u| u["email"] }
      expect(user_emails).to include(trial_user.email)
      
      # Check for free user with specific username
      get "/admin/subscriptions/trials/search", params: { q: "freeuser" }
      json = JSON.parse(response.body)
      user_emails = json["users"].map { |u| u["email"] }
      expect(user_emails).to include(free_user.email)
    end

    it "returns empty array for blank query" do
      get "/admin/subscriptions/trials/search", params: { q: "" }
      json = JSON.parse(response.body)
      expect(json["users"]).to eq([])
    end
  end
end

