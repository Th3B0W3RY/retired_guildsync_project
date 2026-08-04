# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Authentication", type: :request do
  let!(:free_plan) do
    create(:pricing_plan,
           name: "Free",
           price: 0,
           price_display: "$0",
           period: "forever",
           max_guilds: 1,
           max_members_per_guild: 10,
           active: true,
           display_order: 1)
  end

  describe "POST /api/v1/auth/sign_up" do
    context "with valid attributes" do
      it "creates a new user" do
        user_params = {
          user: {
            email: "newuser@example.com",
            username: "newuser",
            password: "password123",
            password_confirmation: "password123"
          }
        }

        expect {
          post "/api/v1/auth/sign_up", params: user_params, as: :json
        }.to change(User, :count).by(1)

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response["user"]["email"]).to eq("newuser@example.com")
        expect(json_response["user"]["username"]).to eq("newuser")
        expect(json_response["token"]).to be_nil
        expect(json_response["message"]).to eq(I18n.t("api.auth.confirmation_required"))

        sub_json = json_response["user"]["current_subscription"]
        expect(sub_json).to be_present
        expect(sub_json["status"]).to eq("active")
        expect(sub_json["pricing_plan"]["name"]).to eq("Free")
        expect(sub_json).not_to include("stripe_subscription_id", "stripe_customer_id", "stripe_price_id")

        # Verify user has free plan subscription
        user = User.find_by(email: "newuser@example.com")
        expect(user.confirmed_at).to be_nil
        expect(user.current_plan).to eq(free_plan)
        expect(user.current_subscription).to be_present
        expect(user.current_subscription.status).to eq("active")
      end

      it "ignores client-supplied auth_method and keeps API sign-up as MFA" do
        user_params = {
          user: {
            email: "nomerge@example.com",
            username: "nomerge",
            password: "password123",
            password_confirmation: "password123",
            auth_method: "google"
          }
        }

        post "/api/v1/auth/sign_up", params: user_params, as: :json
        expect(response).to have_http_status(:created)
        user = User.find_by!(email: "nomerge@example.com")
        expect(user.auth_method).to eq("mfa")
      end

      it "returns a JWT after the user confirms their email" do
        user_params = {
          user: {
            email: "confirm_api@example.com",
            username: "confirmapi",
            password: "password123",
            password_confirmation: "password123"
          }
        }

        post "/api/v1/auth/sign_up", params: user_params, as: :json
        expect(response).to have_http_status(:created)
        user = User.find_by!(email: "confirm_api@example.com")
        user.confirm

        post "/api/v1/auth/sign_in",
             params: { user: { email: "confirm_api@example.com", password: "password123" } },
             as: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["token"]).to be_present
        expect(json_response["message"]).to eq(I18n.t("api.auth.signed_in"))
      end

      it "confirms Playwright test users that request the test MFA bypass" do
        user_params = {
          user: {
            email: "playwright_api@example.com",
            username: "playwrightapi",
            password: "password123",
            password_confirmation: "password123",
            skip_mfa_verification: true
          }
        }

        post "/api/v1/auth/sign_up", params: user_params, as: :json

        expect(response).to have_http_status(:created)
        user = User.find_by!(email: "playwright_api@example.com")
        expect(user.confirmed_at).to be_present
        expect(user.signup_email_verified_at).to be_present
        json_response = JSON.parse(response.body)
        expect(json_response["token"]).to be_present
      end

      it "can create a confirmed test user that still needs MFA setup" do
        user_params = {
          user: {
            email: "playwright_mfa_setup@example.com",
            username: "playwrightmfa",
            password: "password123",
            password_confirmation: "password123",
            test_confirm_email: true,
            test_skip_mfa_auto_setup: true
          }
        }

        post "/api/v1/auth/sign_up", params: user_params, as: :json

        expect(response).to have_http_status(:created)
        user = User.find_by!(email: "playwright_mfa_setup@example.com")
        expect(user.confirmed_at).to be_present
        expect(user.signup_email_verified_at).to be_present
        expect(user.mfa_enabled).to be false
        json_response = JSON.parse(response.body)
        expect(json_response["token"]).to be_present
      end

      it "creates OTP secret for MFA on user creation" do
        user_params = {
          user: {
            email: "mfa@example.com",
            username: "mfauser",
            password: "password123",
            password_confirmation: "password123"
          }
        }

        post "/api/v1/auth/sign_up", params: user_params, as: :json
        user = User.find_by(email: "mfa@example.com")
        expect(user.otp_secret).to be_present
      end
    end

    context "with invalid attributes" do
      it "rejects invalid user data" do
        user_params = {
          user: {
            email: "invalid",
            username: "ab", # too short
            password: "123", # too short
            password_confirmation: "456" # mismatch
          }
        }

        expect {
          post "/api/v1/auth/sign_up", params: user_params, as: :json
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "one account per IP" do
      it "rejects sign_up when another account exists from same IP" do
        skip "No signup_ip column" unless User.column_names.include?("signup_ip")
        create(:user, email: "taken@example.com", username: "takenuser", signup_ip: "203.0.113.1")
        user_params = {
          user: {
            email: "other@example.com",
            username: "otheruser",
            password: "password123",
            password_confirmation: "password123"
          }
        }
        expect {
          post "/api/v1/auth/sign_up", params: user_params, as: :json, headers: { "REMOTE_ADDR" => "203.0.113.1" }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expected_message = I18n.t("errors.attributes.user.one_account_per_ip")
        expect(json["errors"]).to be_a(Array)
        expect(json["errors"]).to include(expected_message)
      end
    end
  end

  describe "POST /api/v1/auth/sign_in" do
    let!(:user) do
      u = create(:user, email: "test@example.com", password: "password123", password_confirmation: "password123")
      create(:subscription, user: u, pricing_plan: free_plan) unless u.subscriptions.any?
      u
    end

    context "with valid credentials" do
      it "signs in successfully" do
        sign_in_params = {
          user: {
            email: "test@example.com",
            password: "password123"
          }
        }

        post "/api/v1/auth/sign_in", params: sign_in_params, as: :json
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["user"]["email"]).to eq("test@example.com")
        expect(json_response["token"]).to be_present
        sub_json = json_response["user"]["current_subscription"]
        expect(sub_json).to be_present
        expect(sub_json["pricing_plan"]["name"]).to eq("Free")
        expect(sub_json).not_to include("stripe_subscription_id", "stripe_customer_id", "stripe_price_id")
      end
    end

    context "with invalid credentials" do
      it "rejects invalid credentials" do
        sign_in_params = {
          user: {
            email: "test@example.com",
            password: "wrongpassword"
          }
        }

        post "/api/v1/auth/sign_in", params: sign_in_params, as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("api.auth.invalid_sign_in"))
      end

      it "rejects unconfirmed users with valid password" do
        u = create(:user, :unconfirmed,
                   email: "unconfirmed_api@example.com",
                   username: "unconfirmedapi",
                   password: "password123",
                   password_confirmation: "password123")
        create(:subscription, user: u, pricing_plan: free_plan) unless u.subscriptions.any?

        post "/api/v1/auth/sign_in",
             params: { user: { email: "unconfirmed_api@example.com", password: "password123" } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("api.auth.unconfirmed_sign_in"))
      end

      it "rejects archived users with valid password" do
        u = create(:user,
                   email: "archived_api@example.com",
                   username: "archivedapi",
                   password: "password123",
                   password_confirmation: "password123",
                   archived: true)
        create(:subscription, user: u, pricing_plan: free_plan) unless u.subscriptions.any?

        post "/api/v1/auth/sign_in",
             params: { user: { email: "archived_api@example.com", password: "password123" } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("api.auth.archived_sign_in"))
      end
    end
  end

  describe "GET /api/v1/auth/me" do
    let(:user) do
      u = create(:user)
      create(:subscription, user: u, pricing_plan: free_plan) unless u.subscriptions.any?
      u
    end

    context "when authenticated" do
      it "returns current user info" do
        # Sign in the user using Devise test helpers
        sign_in user
        get "/api/v1/auth/me", as: :json
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["user"]["id"]).to eq(user.id)
        sub_json = json_response["user"]["current_subscription"]
        expect(sub_json).to be_present
        expect(sub_json["pricing_plan"]["name"]).to eq("Free")
        expect(sub_json).not_to include("stripe_subscription_id", "stripe_customer_id", "stripe_price_id")
      end
    end

    context "when unauthenticated" do
      it "rejects the request" do
        get "/api/v1/auth/me", as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("api.v1.authentication_required"))
      end
    end

    context "with Bearer JWT from sign_in (stateless)" do
      let!(:jwt_user) do
        u = create(:user, email: "jwt_me@example.com", password: "password123", password_confirmation: "password123")
        create(:subscription, user: u, pricing_plan: free_plan) unless u.subscriptions.any?
        u
      end

      it "authenticates /me using the token from sign_in without a browser session" do
        post "/api/v1/auth/sign_in",
             params: { user: { email: "jwt_me@example.com", password: "password123" } },
             as: :json

        expect(response).to have_http_status(:ok)
        token = JSON.parse(response.body)["token"]
        expect(token).to be_present

        get "/api/v1/auth/me",
            headers: { "Authorization" => "Bearer #{token}" },
            as: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["user"]["id"]).to eq(jwt_user.id)
        expect(json_response["user"]["email"]).to eq("jwt_me@example.com")
      end

      it "rejects /me when the Bearer token is not a valid JWT" do
        get "/api/v1/auth/me",
            headers: { "Authorization" => "Bearer not-a-valid-jwt" },
            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("api.v1.authentication_required"))
      end
    end
  end

  describe "DELETE /api/v1/auth/sign_out" do
    let!(:user) do
      u = create(:user, email: "jwt_out@example.com", password: "password123", password_confirmation: "password123")
      create(:subscription, user: u, pricing_plan: free_plan) unless u.subscriptions.any?
      u
    end

    it "returns success when the client was authenticated with Bearer JWT" do
      post "/api/v1/auth/sign_in",
           params: { user: { email: "jwt_out@example.com", password: "password123" } },
           as: :json
      token = JSON.parse(response.body)["token"]

      delete "/api/v1/auth/sign_out",
             headers: { "Authorization" => "Bearer #{token}" },
             as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["message"]).to eq(I18n.t("api.auth.signed_out"))
    end
  end
end
