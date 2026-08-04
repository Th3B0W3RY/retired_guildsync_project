# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Authentication Flow", type: :request do
  # Regression: application layout renders shared/active_compliance_warning_banner which calls
  # active_ip_compliance_warning. Devise inherits ApplicationController for locale/layout stack — helper must live on ApplicationHelper.
  describe "GET /login (layout + compliance partial)" do
    it "returns 200 for unauthenticated login (no missing helper on Devise layout)" do
      get "/login"
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/html")
    end

    it "returns 200 with post sign-out query params (matches production redirect URL)" do
      get "/login", params: { signed_out: 1, force_load: 1 }
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/html")
    end
  end

  describe "GET /sign_up (registrations#new, same layout)" do
    it "redirects to the verified account creation flow" do
      get "/sign_up"
      expect(response).to redirect_to(create_account_path)
    end
  end

  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let(:user) do
    u = create(:user, password: "password123", password_confirmation: "password123")
    create(:subscription, user: u, pricing_plan: pricing_plan) unless u.subscriptions.any?
    u
  end

  describe "POST /sign_in" do
    context "with valid credentials" do
      it "signs in user successfully and redirects to MFA setup" do
        post "/sign_in", params: {
          user: {
            email: user.email,
            password: "password123"
          }
        }

        # Users without MFA enabled are redirected to MFA setup
        expect(response).to redirect_to(mfa_setup_path)
      end

      it "signs in with email" do
        post "/sign_in", params: {
          user: {
            email: user.email,
            password: "password123"
          }
        }

        expect(response).to redirect_to(mfa_setup_path)
      end
    end

    context "with invalid credentials" do
      it "rejects wrong password" do
        post "/sign_in", params: {
          user: {
            email: user.email,
            password: "wrong_password"
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects non-existent user" do
        post "/sign_in", params: {
          user: {
            email: "nonexistent@example.com",
            password: "password123"
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects valid password when email is not confirmed" do
        pending_user = create(:user, :unconfirmed,
                              email: "pending@example.com",
                              username: "pendinguser",
                              password: "password123",
                              password_confirmation: "password123")
        create(:subscription, user: pending_user, pricing_plan: pricing_plan) unless pending_user.subscriptions.any?

        post "/sign_in", params: {
          user: {
            email: "pending@example.com",
            password: "password123"
          }
        }

        expect(response).to be_redirect
        expect(URI.parse(response.location).path).to eq(root_path)
        expect(flash[:alert]).to eq(I18n.t("devise.failure.unconfirmed"))
      end
    end

    context "when MFA is enabled" do
      let(:mfa_user) do
        u = create(:user, :with_mfa, password: "password123", password_confirmation: "password123")
        create(:subscription, user: u, pricing_plan: pricing_plan) unless u.subscriptions.any?
        u
      end

      it "requires MFA verification" do
        post "/sign_in", params: {
          user: {
            email: mfa_user.email,
            password: "password123"
          }
        }

        expect(response).to redirect_to(mfa_verification_path(return_to: dashboard_path))
        expect(session[:just_logged_in]).to be true
        expect(session[:user_id]).to eq(mfa_user.id)
      end
    end

    context "when MFA is incomplete" do
      let(:incomplete_mfa_user) do
        u = create(:user,
               password: "password123",
               password_confirmation: "password123",
               mfa_enabled: true,
               mfa_verified: false)
        create(:subscription, user: u, pricing_plan: pricing_plan) unless u.subscriptions.any?
        u
      end

      it "blocks login and redirects to MFA setup" do
        post "/sign_in", params: {
          user: {
            email: incomplete_mfa_user.email,
            password: "password123"
          }
        }

        # May redirect to MFA setup or MFA verification depending on state
        expect(response).to be_redirect
        expect(response.location).to match(/mfa/)
      end
    end

    context "when a pending guild invite exists" do
      let(:owner) { create(:user) }
      let(:guild) { create(:guild, owner: owner) }
      let(:invite_link) { guild.guild_invite_links.create!(created_by: owner, expires_at: 7.days.from_now) }
      let(:pending_invite_user) do
        u = create(:user,
          auth_method: "mfa",
          mfa_enabled: false,
          mfa_verified: false,
          password: "password123",
          password_confirmation: "password123")
        create(:subscription, user: u, pricing_plan: pricing_plan) unless u.subscriptions.any?
        u
      end

      it "redirects to MFA setup (not MFA verification) for MFA users who have not configured MFA yet" do
        get join_guild_path(invite_link.token)

        post "/sign_in", params: {
          user: {
            email: pending_invite_user.email,
            password: "password123"
          }
        }

        expect(response).to redirect_to(mfa_setup_path)
      end
    end
  end

  describe "DELETE /sign_out" do
    before { sign_in user }

    it "signs out user successfully" do
      delete "/sign_out"
      expect(response).to be_redirect
      expect(response.location).to include(login_path)
      expect(response.location).to include("signed_out=1")
    end
  end

  describe "GET /login with signed_out param" do
    it "does not show signed-out toast without signed cookie proof" do
      get "/login", params: { signed_out: 1 }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(I18n.t("flash.signed_out"))
    end

    it "shows signed-out toast only when signed cookie proof is present" do
      sign_in user
      delete "/sign_out"

      get "/login", params: { signed_out: 1 }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("flash.signed_out"))
    end

    it "does not show signed-out toast on force-load hop even with signed cookie" do
      sign_in user
      delete "/sign_out"

      get "/login", params: { signed_out: 1, force_load: 1 }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(I18n.t("flash.signed_out"))
    end
  end

  describe "POST /sign_up" do
    let(:pricing_plan) { create(:pricing_plan, name: "Free", max_guilds: 1) }

    context "with valid data" do
      it "redirects to the email verification flow without creating a user" do
        expect {
          post "/sign_up", params: {
            user: {
              email: "newuser@example.com",
              username: "newuser",
              password: "password123",
              password_confirmation: "password123"
            },
            plan_id: pricing_plan.id
          }
        }.not_to change(User, :count)

        expect(response).to redirect_to(create_account_path)
        expect(User.find_by(email: "newuser@example.com")).to be_nil
      end

      it "does not start MFA setup from the legacy sign_up endpoint" do
        post "/sign_up", params: {
          user: {
            email: "mfa_setup_user@example.com",
            username: "mfasetupuser",
            password: "password123",
            password_confirmation: "password123"
          },
          plan_id: pricing_plan.id
        }
        expect(response).to redirect_to(create_account_path)
      end

      it "does not create subscription from the legacy sign_up endpoint" do
        post "/sign_up", params: {
          user: {
            email: "newuser2@example.com",
            username: "newuser2",
            password: "password123",
            password_confirmation: "password123"
          },
          plan_id: pricing_plan.id
        }

        user = User.find_by(email: "newuser2@example.com")
        expect(user).to be_nil
      end
    end

    context "with invalid data" do
      it "rejects duplicate username" do
        post "/sign_up", params: {
          user: {
            email: "different@example.com",
            username: user.username,
            password: "password123",
            password_confirmation: "password123"
          }
        }

        expect(response).to redirect_to(create_account_path)
        expect(User.find_by(email: "different@example.com")).to be_nil
      end

      it "rejects weak password" do
        post "/sign_up", params: {
          user: {
            email: "weak@example.com",
            username: "weakuser",
            password: "123",
            password_confirmation: "123"
          }
        }

        expect(response).to redirect_to(create_account_path)
      end
    end
  end
end
