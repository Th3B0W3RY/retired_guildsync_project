# frozen_string_literal: true

require "erb"
require 'rails_helper'

RSpec.describe "Admin::Users", type: :request do
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

  describe "GET /admin/users" do
    let!(:user1) { create(:user, email: "john@example.com", username: "john_doe") }
    let!(:user2) { create(:user, email: "jane@example.com", username: "jane_smith") }

    it "lists all users" do
      get "/admin/users"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.users.index.page_title"))
      expect(response.body).to include(I18n.t("admin.users.index.search_submit"))
      expect(response.body).to include(user1.email)
      expect(response.body).to include(user2.email)
    end

    it "searches users by email" do
      get "/admin/users", params: { q: "john" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(user1.email)
      expect(response.body).not_to include(user2.email)
    end

    it "searches users by username" do
      get "/admin/users", params: { q: "jane" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(user2.email)
      expect(response.body).not_to include(user1.email)
    end

    it "returns frame-only HTML when Turbo-Frame targets results" do
      get "/admin/users",
        params: { q: "john" },
        headers: { "Turbo-Frame" => Admin::UsersController::USERS_INDEX_RESULTS_FRAME }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="#{Admin::UsersController::USERS_INDEX_RESULTS_FRAME}"))
      expect(response.body).to include(user1.email)
      expect(response.body).not_to include(user2.email)
      expect(response.body).not_to include(I18n.t("admin.users.index.page_title"))
    end
  end

  describe "GET /admin/users/search" do
    let!(:user1) { create(:user, email: "john@example.com", username: "john_doe") }
    let!(:user2) { create(:user, email: "jane@example.com", username: "jane_smith") }

    it "returns JSON with user suggestions" do
      get "/admin/users/search", params: { q: "john" }
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")
      
      json = JSON.parse(response.body)
      expect(json).to have_key("users")
      expect(json["users"].length).to be > 0
      expect(json["users"].first).to have_key("email")
      expect(json["users"].first).to have_key("username")
    end

    it "returns empty array for blank query" do
      get "/admin/users/search", params: { q: "" }
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["users"]).to eq([])
    end

    it "searches by email" do
      get "/admin/users/search", params: { q: "john@example.com" }
      json = JSON.parse(response.body)
      expect(json["users"].any? { |u| u["email"] == "john@example.com" }).to be true
    end

    it "searches by username" do
      get "/admin/users/search", params: { q: "john_doe" }
      json = JSON.parse(response.body)
      expect(json["users"].any? { |u| u["username"] == "john_doe" }).to be true
    end

    it "limits results to 10" do
      15.times { |i| create(:user, email: "user#{i}@test.com", username: "user#{i}") }
      get "/admin/users/search", params: { q: "user" }
      json = JSON.parse(response.body)
      expect(json["users"].length).to be <= 10
    end
  end

  describe "GET /admin/users/:id" do
    let(:pricing_plan) { create(:pricing_plan, name: "Free Plan") }
    let(:user) { create(:user, skip_free_plan_subscription: true) }
    let!(:subscription) { create(:subscription, user: user, pricing_plan: pricing_plan, status: :trialing, trial_ends_at: 7.days.from_now) }

    it "shows user details" do
      get "/admin/users/#{user.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.users.show.page_title"))
      expect(response.body).to include(user.email)
      expect(response.body).to include(user.username)
      expect(response.body).to include('id="admin_user_show_flash"')
      expect(response.body).to include('id="admin_user_subscription_trial_panel"')
      expect(response.body).to include('id="admin_user_compliance_panel"')
    end

    it "shows subscription information" do
      get "/admin/users/#{user.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Free Plan")
      expect(response.body).to include(I18n.t("admin.users.show.trial_badge"))
      expect(response.body).to include(I18n.t("admin.users.show.subscription_status.trialing"))
    end

    it "renders frame-only body when Turbo-Frame requests main" do
      get "/admin/users/#{user.id}",
        headers: { "Turbo-Frame" => Admin::UsersController::USERS_SHOW_MAIN_FRAME }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="admin_users_show_main"))
      expect(response.body).to include(user.email)
      expect(response.body).not_to include(I18n.t("admin.users.show.page_title"))
    end
  end

  describe "PATCH /admin/users/:id/trial" do
    let(:pricing_plan) { create(:pricing_plan, name: "Free Plan") }
    let(:user) { create(:user, skip_free_plan_subscription: true) }
    let!(:subscription) { create(:subscription, user: user, pricing_plan: pricing_plan, status: :trialing, trial_ends_at: 7.days.from_now) }

    it "extends trial by 1 week" do
      original_end = subscription.trial_ends_at
      patch "/admin/users/#{user.id}/trial", params: { action_type: "extend_1_week" }

      expect(response).to redirect_to(admin_user_path(user))
      expect(flash[:notice]).to eq(I18n.t("admin.users.trial_flash.updated"))
      subscription.reload
      expect(subscription.trial_ends_at).to be > original_end
    end

    it "extends trial by 2 weeks" do
      original_end = subscription.trial_ends_at
      patch "/admin/users/#{user.id}/trial", params: { action_type: "extend_2_weeks" }

      expect(response).to redirect_to(admin_user_path(user))
      subscription.reload
      expect(subscription.trial_ends_at).to be > original_end
    end

    it "extends trial by 1 month" do
      original_end = subscription.trial_ends_at
      patch "/admin/users/#{user.id}/trial", params: { action_type: "extend_1_month" }

      expect(response).to redirect_to(admin_user_path(user))
      subscription.reload
      expect(subscription.trial_ends_at).to be > original_end
    end

    it "extends trial to custom date" do
      custom_date = 30.days.from_now.to_date
      patch "/admin/users/#{user.id}/trial", params: { action_type: "extend_custom", custom_date: custom_date.to_s }

      expect(response).to redirect_to(admin_user_path(user))
      subscription.reload
      expect(subscription.trial_ends_at.to_date).to eq(custom_date)
    end

    it "handles invalid custom date" do
      patch "/admin/users/#{user.id}/trial", params: { action_type: "extend_custom", custom_date: "invalid-date" }

      expect(response).to redirect_to(admin_user_path(user))
      expect(flash[:alert]).to eq(I18n.t("admin.users.trial_flash.invalid_date"))
    end

    it "handles missing custom date" do
      patch "/admin/users/#{user.id}/trial", params: { action_type: "extend_custom", custom_date: "" }

      expect(response).to redirect_to(admin_user_path(user))
      expect(flash[:alert]).to eq(I18n.t("admin.users.trial_flash.select_date"))
    end

    it "removes trial" do
      expect(subscription.status).to eq("trialing")
      patch "/admin/users/#{user.id}/trial", params: { action_type: "remove" }

      expect(response).to redirect_to(admin_user_path(user))
      subscription.reload
      expect(subscription.status).to eq("active")
      expect(subscription.trial_ends_at).to be_nil
    end

    it "adds new trial" do
      new_plan = create(:pricing_plan, name: "Pro Plan")
      subscription.update!(status: :active, trial_ends_at: nil)

      patch "/admin/users/#{user.id}/trial", params: { action_type: "add", plan_id: new_plan.id }

      expect(response).to redirect_to(admin_user_path(user))
      user.reload
      new_subscription = user.current_subscription
      expect(new_subscription.pricing_plan).to eq(new_plan)
      expect(new_subscription.status).to eq("trialing")
      expect(new_subscription.trial_ends_at).to be_present
    end

    it "returns turbo-stream subscription panel refresh on extend_1_week" do
      patch "/admin/users/#{user.id}/trial",
        params: { action_type: "extend_1_week" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('action="replace"', "admin_user_subscription_trial_panel")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.users.trial_flash.updated"))
      )
    end

    it "returns turbo-stream alert flash when custom date is missing" do
      patch "/admin/users/#{user.id}/trial",
        params: { action_type: "extend_custom", custom_date: "" },
        headers: { "Accept" => Mime[:turbo_stream].to_s }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="update"', "admin_user_show_flash")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("admin.users.trial_flash.select_date"))
      )
    end
  end

  describe "POST /admin/users/:id/reactivate_account" do
    let(:target) do
      create(:user, email: "reac@example.com").tap do |u|
        u.update_columns(
          archived: true,
          account_closed_at: Time.current,
          account_deletion_started_at: Time.current,
          updated_at: Time.current
        )
      end
    end

    it "clears closure flags when purge has not completed" do
      post reactivate_account_admin_user_path(target)

      expect(response).to redirect_to(admin_user_path(target))
      target.reload
      expect(target.archived).to be false
      expect(target.account_closed_at).to be_nil
      expect(target.account_deletion_started_at).to be_nil
      expect(target.account_closure_soft_completed_at).to be_nil
    end

    it "rejects when data was already purged" do
      target.update_columns(account_data_purged_at: Time.current, updated_at: Time.current)
      post reactivate_account_admin_user_path(target)

      expect(response).to redirect_to(admin_user_path(target))
      expect(flash[:alert]).to eq(I18n.t("admin.users.reactivate.hard_purged"))
    end

    it "rejects when outside the retention window" do
      target.update_columns(
        account_closed_at: 7.months.ago,
        account_deletion_started_at: 7.months.ago,
        updated_at: Time.current
      )
      post reactivate_account_admin_user_path(target)

      expect(response).to redirect_to(admin_user_path(target))
      months = (SoftDeletable::RETENTION_PERIOD / 1.month).to_i
      expect(flash[:alert]).to eq(I18n.t("admin.users.reactivate.outside_retention", months: months))
    end
  end
end

