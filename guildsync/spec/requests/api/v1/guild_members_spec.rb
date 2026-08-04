# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Guild Members", type: :request do
  # Create a test plan with specific limits (not "Free" to avoid conflicts)
  let!(:test_plan) do
    create(:pricing_plan,
           name: "Test Plan - Member Limit",
           price: 0,
           price_display: "$0",
           period: "forever",
           max_guilds: 1,
           max_members_per_guild: 10,
           active: true,
           display_order: 1)
  end

  let(:owner) do
    # Skip automatic Free plan subscription so we can create the test subscription
    u = create(:user, skip_free_plan_subscription: true)
    create(:subscription, user: u, pricing_plan: test_plan)
    # Set up MFA for API authentication (API requires MFA to be set up)
    u.generate_otp_secret_if_needed unless u.otp_secret.present?
    u.update!(mfa_enabled: true, mfa_verified: true)
    u
  end
  let(:guild) { create(:guild, owner: owner) }

  # Helper to authenticate user for API requests
  # The API BaseController inherits MFA checks from ApplicationController
  # We need to sign in the user and set up MFA verification in the session
  def authenticate_api_user(user)
    sign_in user
    # Use the helper that makes a request to establish session context
    set_mfa_verified_in_session
  end

  describe "POST /api/v1/guilds/:guild_id/members" do
    before do
      authenticate_api_user(owner)
    end

    let(:new_member) do
      # Skip automatic Free plan subscription so we can create the test subscription
      u = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: test_plan)
      u
    end

    context "with valid attributes" do
      it "adds a member to a guild" do
        member_params = {
          user_id: new_member.id,
          guild_member: {
            role: "member",
            status: "active"
          }
        }

        # Guild factory creates owner as a member, so we check guild-specific count
        expect {
          post "/api/v1/guilds/#{guild.id}/members", params: member_params, headers: auth_headers_with_token(owner), as: :json
        }.to change { guild.guild_members.count }.by(1)

        expect(response).to have_http_status(:created)
        expect(guild.members).to include(new_member)
      end
    end

    context "with duplicate member" do
      it "prevents adding duplicate members" do
        create(:guild_member, guild: guild, user: new_member)

        member_params = {
          user_id: new_member.id,
          guild_member: {
            role: "member"
          }
        }

        post "/api/v1/guilds/#{guild.id}/members", params: member_params, headers: auth_headers_with_token(owner), as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when member limit is reached" do
      it "enforces member limit" do
        # Owner is already a member (created by factory), so we need to add (max - 1) more members
        # to reach the limit, then try to add one more
        (test_plan.max_members_per_guild - 1).times do
          # Skip automatic Free plan subscription so we can create the test subscription
          member = create(:user, skip_free_plan_subscription: true)
          create(:subscription, user: member, pricing_plan: test_plan)
          create(:guild_member, guild: guild, user: member)
        end

        member_params = {
          user_id: new_member.id,
          guild_member: {
            role: "member"
          }
        }

        post "/api/v1/guilds/#{guild.id}/members", params: member_params, headers: auth_headers_with_token(owner), as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /api/v1/guilds/:guild_id/members" do
    it "returns not found when the user cannot access the guild" do
      stranger = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: stranger, pricing_plan: test_plan)
      stranger.generate_otp_secret_if_needed unless stranger.otp_secret.present?
      stranger.update!(mfa_enabled: true, mfa_verified: true)
      authenticate_api_user(stranger)

      get "/api/v1/guilds/#{guild.id}/members", headers: auth_headers_with_token(stranger), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    before do
      authenticate_api_user(owner)
    end

    let!(:member1) do
      u = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: test_plan)
      create(:guild_member, guild: guild, user: u, role: :member)
    end
    let!(:member2) do
      u = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: test_plan)
      create(:guild_member, guild: guild, user: u, role: :admin)
    end

    it "lists all guild members" do
      get "/api/v1/guilds/#{guild.id}/members", headers: auth_headers_with_token(owner), as: :json
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["members"].length).to eq(3) # owner + 2 members
      nested_user = json_response["members"].find { |m| m["user"]["id"] == member1.user.id }["user"]
      expect(nested_user).not_to have_key("current_subscription")

      expect(json_response["pagination"]).to include(
        "page" => 1,
        "per_page" => 25,
        "total_count" => 3,
        "total_pages" => 1
      )
    end

    it "supports page and per_page for members list" do
      get "/api/v1/guilds/#{guild.id}/members", params: { page: 2, per_page: 1 }, headers: auth_headers_with_token(owner), as: :json
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["members"].length).to eq(1)
      expect(json_response["pagination"]).to include(
        "page" => 2,
        "per_page" => 1,
        "total_count" => 3,
        "total_pages" => 3
      )
    end

    it "returns not_found with access_denied when the defensive membership check fails" do
      member_user = member1.user
      member_user.generate_otp_secret_if_needed unless member_user.otp_secret.present?
      member_user.update!(mfa_enabled: true, mfa_verified: true)
      authenticate_api_user(member_user)

      allow_any_instance_of(Guild).to receive(:guild_members).and_wrap_original do |m, *args, **kwargs|
        relation = m.call(*args, **kwargs)
        next relation unless relation.proxy_association.owner.id == guild.id

        allow(relation).to receive(:exists?).and_wrap_original do |em, *eargs, **ekwargs|
          uid = ekwargs[:user_id] || (eargs.first.is_a?(Hash) ? eargs.first[:user_id] : nil)
          next false if uid == member_user.id

          em.call(*eargs, **ekwargs)
        end
        relation
      end

      get "/api/v1/guilds/#{guild.id}/members", headers: auth_headers_with_token(member_user), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "PATCH /api/v1/guilds/:guild_id/members/:id" do
    before do
      authenticate_api_user(owner)
    end

    let(:member) do
      u = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: test_plan)
      u
    end
    let!(:guild_member) { create(:guild_member, guild: guild, user: member, role: :member) }

    it "updates member role" do
      update_params = {
        guild_member: {
          role: "admin"
        }
      }

      patch "/api/v1/guilds/#{guild.id}/members/#{guild_member.id}", params: update_params, headers: auth_headers_with_token(owner), as: :json
      expect(response).to have_http_status(:ok)
      guild_member.reload
      expect(guild_member.role).to eq("admin")
    end

    it "returns not found with access_denied for an unknown member id" do
      patch "/api/v1/guilds/#{guild.id}/members/0",
            params: { guild_member: { role: "admin" } },
            headers: auth_headers_with_token(owner),
            as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "returns not found with access_denied when the member belongs to another guild" do
      other_owner = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: other_owner, pricing_plan: test_plan)
      other_guild = create(:guild, owner: other_owner)
      other_member = create(:guild_member, guild: other_guild, user: create(:user))

      patch "/api/v1/guilds/#{guild.id}/members/#{other_member.id}",
            params: { guild_member: { role: "admin" } },
            headers: auth_headers_with_token(owner),
            as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "DELETE /api/v1/guilds/:guild_id/members/:id" do
    before do
      authenticate_api_user(owner)
    end

    let(:member) { create(:user) }
    let!(:guild_member) { create(:guild_member, guild: guild, user: member) }

    it "removes a member from guild" do
      expect {
        delete "/api/v1/guilds/#{guild.id}/members/#{guild_member.id}", headers: auth_headers_with_token(owner), as: :json
      }.to change(GuildMember, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "returns not found with access_denied for an unknown member id" do
      expect {
        delete "/api/v1/guilds/#{guild.id}/members/0", headers: auth_headers_with_token(owner), as: :json
      }.not_to change(GuildMember, :count)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "GET /api/v1/guilds/:guild_id/members/:id" do
    before do
      authenticate_api_user(owner)
    end

    let(:member_user) do
      u = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: u, pricing_plan: test_plan)
      u
    end
    let!(:guild_member) { create(:guild_member, guild: guild, user: member_user, role: :member) }

    it "returns the guild member" do
      get "/api/v1/guilds/#{guild.id}/members/#{guild_member.id}", headers: auth_headers_with_token(owner), as: :json
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["id"]).to eq(guild_member.id)
      expect(json["role"]).to eq("member")
      expect(json["user"]["id"]).to eq(member_user.id)
    end

    it "returns not found with access_denied for an unknown member id" do
      get "/api/v1/guilds/#{guild.id}/members/0", headers: auth_headers_with_token(owner), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "returns not found with access_denied when the member belongs to another guild" do
      other_owner = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: other_owner, pricing_plan: test_plan)
      other_guild = create(:guild, owner: other_owner)
      other_member = create(:guild_member, guild: other_guild, user: create(:user))

      get "/api/v1/guilds/#{guild.id}/members/#{other_member.id}", headers: auth_headers_with_token(owner), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "returns not found with access_denied for a non-member of the guild" do
      stranger = create(:user, skip_free_plan_subscription: true)
      create(:subscription, user: stranger, pricing_plan: test_plan)
      stranger.generate_otp_secret_if_needed unless stranger.otp_secret.present?
      stranger.update!(mfa_enabled: true, mfa_verified: true)
      authenticate_api_user(stranger)

      get "/api/v1/guilds/#{guild.id}/members/#{guild_member.id}", headers: auth_headers_with_token(stranger), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end
end

