# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Guilds", type: :request do
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
    # Reload to get subscription from callback (which looks for plan named "Free")
    u.reload
    # Set up MFA for API authentication (API requires MFA to be set up)
    # Generate OTP secret if not present
    u.generate_otp_secret_if_needed unless u.otp_secret.present?
    u.update!(mfa_enabled: true, mfa_verified: true)
    u
  end

  # Helper to authenticate user for API requests
  # The API BaseController inherits MFA checks from ApplicationController
  # We need to sign in the user and set up MFA verification in the session
  # Session is only available after making a request, so we use set_mfa_verified_in_session
  def authenticate_api_user(user)
    sign_in user
    # Use the helper that makes a request to establish session context
    set_mfa_verified_in_session
  end

  describe "POST /api/v1/guilds" do
    before do
      authenticate_api_user(user)
    end

    context "with valid attributes" do
      it "creates a guild" do
        
        guild_params = {
          guild: {
            name: "Test Guild",
            description: "A test guild"
          }
        }

        expect {
          post "/api/v1/guilds", params: guild_params, headers: auth_headers_with_token(user), as: :json
        }.to change(Guild, :count).by(1)

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response["guild"]["name"]).to eq("Test Guild")
        expect(json_response["guild"]["owner_id"]).to eq(user.id)

        # Verify owner is added as member
        guild = Guild.find(json_response["guild"]["id"])
        expect(guild.members).to include(user)
        expect(guild.guild_members.find_by(user: user).role).to eq("owner")
      end
    end

    context "when guild limit is reached" do
      it "prevents creating guild" do
        create(:guild, owner: user) # Free plan allows 1 guild

        guild_params = {
          guild: {
            name: "Second Guild",
            description: "Should fail"
          }
        }

        post "/api/v1/guilds", params: guild_params, headers: auth_headers_with_token(user), as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with duplicate name" do
      it "validates guild name uniqueness per owner" do
        create(:guild, owner: user, name: "My Guild")

        guild_params = {
          guild: {
            name: "My Guild",
            description: "Duplicate name"
          }
        }

        post "/api/v1/guilds", params: guild_params, headers: auth_headers_with_token(user), as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /api/v1/guilds" do
    before do
      authenticate_api_user(user)
    end

    let!(:guild) { create(:guild, owner: user) }
    let!(:other_guild) do
      g = create(:guild)
      create(:guild_member, guild: g, user: user, role: :member)
      g
    end

    it "lists all guilds for the user" do
      get "/api/v1/guilds", headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["guilds"].length).to eq(2)
      expect(json_response["guilds"].map { |record| record["id"] }).to include(guild.id, other_guild.id)
      expect(json_response["pagination"]).to include(
        "page" => 1,
        "per_page" => 25,
        "total_count" => 2,
        "total_pages" => 1
      )
    end

    it "paginates list endpoints with page and per_page params" do
      get "/api/v1/guilds", params: { page: 2, per_page: 1 }, headers: auth_headers_with_token(user), as: :json
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
  end

  describe "GET /api/v1/guilds/:id" do
    let!(:guild) { create(:guild, owner: user, publicly_listed: false) }

    context "when authorized" do
      before do
        authenticate_api_user(user)
      end

      it "shows a specific guild" do
        get "/api/v1/guilds/#{guild.id}", headers: auth_headers_with_token(user), as: :json
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["guild"]["id"]).to eq(guild.id)
        expect(json_response["guild"]["name"]).to eq(guild.name)
      end
    end

    context "when unauthorized" do
      let(:other_user) do
        u = create(:user)
        create(:subscription, user: u, pricing_plan: free_plan) unless u.subscriptions.any?
        # Set up MFA for API authentication
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end

      before do
        authenticate_api_user(other_user)
      end

      it "returns not found without leaking private guild ids" do
        guild.update!(publicly_listed: false)
        expect(guild.reload.publicly_listed).to be false
        expect(other_user.id).not_to eq(user.id)
        expect(GuildPolicy.new(other_user, guild).show?).to be false

        get "/api/v1/guilds/#{guild.id}", headers: auth_headers_with_token(other_user), as: :json
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      end
    end

    context "when guild is publicly listed" do
      let!(:guild) { create(:guild, owner: user, publicly_listed: true) }

      before { authenticate_api_user(other_user) }

      let(:other_user) do
        u = create(:user)
        create(:subscription, user: u, pricing_plan: free_plan) unless u.subscriptions.any?
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end

      it "allows show for a non-member" do
        get "/api/v1/guilds/#{guild.id}", headers: auth_headers_with_token(other_user), as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("guild", "id")).to eq(guild.id)
      end
    end
  end

  describe "PATCH /api/v1/guilds/:id" do
    before do
      authenticate_api_user(user)
    end

    let!(:guild) { create(:guild, owner: user, name: "Original Name") }

    it "updates guild information" do
      update_params = {
        guild: {
          name: "Updated Name",
          description: "Updated description"
        }
      }

      patch "/api/v1/guilds/#{guild.id}", params: update_params, headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:ok)
      guild.reload
      expect(guild.name).to eq("Updated Name")
      expect(guild.description).to eq("Updated description")
    end
  end

  describe "DELETE /api/v1/guilds/:id" do
    before do
      authenticate_api_user(user)
    end

    let!(:guild) { create(:guild, owner: user) }

    it "deletes a guild" do
      expect {
        delete "/api/v1/guilds/#{guild.id}", headers: auth_headers_with_token(user), as: :json
      }.to change(Guild, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end

