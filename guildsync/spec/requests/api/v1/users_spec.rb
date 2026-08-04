# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Users", type: :request do
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

  let(:user) do
    u = create(:user)
    u.generate_otp_secret_if_needed unless u.otp_secret.present?
    u.update!(mfa_enabled: true, mfa_verified: true)
    u
  end

  def authenticate_api_user(user)
    sign_in user
    set_mfa_verified_in_session
  end

  describe "GET /api/v1/users/:id" do
    before do
      authenticate_api_user(user)
      create(:subscription, user: user, pricing_plan: free_plan) unless user.subscriptions.any?
    end

    it "includes current_subscription on own profile" do
      get "/api/v1/users/#{user.id}", headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["current_subscription"]["status"]).to eq("active")
      expect(json["current_subscription"]["pricing_plan"]["name"]).to eq("Free")
      expect(json["current_subscription"]).not_to include("stripe_subscription_id", "stripe_customer_id", "stripe_price_id")
    end

    it "returns 404 for another user's id (no User.find / existence leak)" do
      other = create(:user)
      other.generate_otp_secret_if_needed unless other.otp_secret.present?
      other.update!(mfa_enabled: true, mfa_verified: true)

      get "/api/v1/users/#{other.id}", headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "returns 404 for an unknown user id" do
      get "/api/v1/users/0", headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "GET /api/v1/users/:id/guilds" do
    let!(:owned_guild) { create(:guild, owner: user) }
    let!(:member_guild) do
      guild = create(:guild)
      create(:guild_member, guild: guild, user: user, role: :member)
      guild
    end

    before do
      authenticate_api_user(user)
    end

    it "returns paginated guilds for the user" do
      get "/api/v1/users/#{user.id}/guilds", headers: auth_headers_with_token(user), as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["guilds"].length).to eq(2)
      expect(json_response["guilds"].map { |record| record["id"] }).to include(owned_guild.id, member_guild.id)
      expect(json_response["pagination"]).to include(
        "page" => 1,
        "per_page" => 25,
        "total_count" => 2,
        "total_pages" => 1
      )
    end

    it "supports page and per_page params" do
      get "/api/v1/users/#{user.id}/guilds",
          params: { page: 2, per_page: 1 },
          headers: auth_headers_with_token(user),
          as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["guilds"].length).to eq(1)
      expect(json_response["pagination"]).to include(
        "page" => 2,
        "per_page" => 1,
        "total_count" => 2,
        "total_pages" => 2
      )
    end

    it "returns 404 when requesting another user's guild list" do
      stranger = create(:user)
      stranger.generate_otp_secret_if_needed unless stranger.otp_secret.present?
      stranger.update!(mfa_enabled: true, mfa_verified: true)

      get "/api/v1/users/#{stranger.id}/guilds", headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "PATCH /api/v1/users/:id" do
    before do
      authenticate_api_user(user)
      create(:subscription, user: user, pricing_plan: free_plan) unless user.subscriptions.any?
    end

    it "returns 404 when updating another user" do
      other = create(:user)
      other.generate_otp_secret_if_needed unless other.otp_secret.present?
      other.update!(mfa_enabled: true, mfa_verified: true)

      patch "/api/v1/users/#{other.id}",
            params: { user: { username: "hacked" } },
            headers: auth_headers_with_token(user),
            as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      expect(other.reload.username).not_to eq("hacked")
    end
  end

  describe "POST /api/v1/users/:id/archive" do
    before do
      authenticate_api_user(user)
      create(:subscription, user: user, pricing_plan: free_plan) unless user.subscriptions.any?
    end

    it "archives the current user and returns api.users.account_archived" do
      expect(user.reload.archived?).to be(false)

      post "/api/v1/users/#{user.id}/archive", headers: auth_headers_with_token(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to eq(I18n.t("api.users.account_archived"))
      expect(user.reload.archived?).to be(true)
    end

    it "returns 404 when archiving another user" do
      other = create(:user)
      other.generate_otp_secret_if_needed unless other.otp_secret.present?
      other.update!(mfa_enabled: true, mfa_verified: true)

      expect {
        post "/api/v1/users/#{other.id}/archive", headers: auth_headers_with_token(user), as: :json
      }.not_to change { other.reload.archived? }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end
end
