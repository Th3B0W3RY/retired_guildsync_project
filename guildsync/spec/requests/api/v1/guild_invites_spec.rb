# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Guild Invites", type: :request do
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

  let(:owner) do
    u = create(:user)
    u.reload
    u.generate_otp_secret_if_needed unless u.otp_secret.present?
    u.update!(mfa_enabled: true, mfa_verified: true)
    u
  end
  let(:guild) { create(:guild, owner: owner) }

  let(:invited_user) do
    u = create(:user)
    u.reload
    u.generate_otp_secret_if_needed unless u.otp_secret.present?
    u.update!(mfa_enabled: true, mfa_verified: true)
    u
  end

  def authenticate_api_user(user)
    sign_in user
    set_mfa_verified_in_session
  end

  describe "POST /api/v1/guilds/:guild_id/invites" do
    before { authenticate_api_user(owner) }

    it "creates an invite and returns 201" do
      expect {
        post "/api/v1/guilds/#{guild.id}/invites",
             params: { invite: { user_id: invited_user.id } },
             headers: auth_headers_with_token(owner),
             as: :json
      }.to change(GuildInvite, :count).by(1)

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json["status"]).to eq("pending")
      expect(json["user"]["id"]).to eq(invited_user.id)
      expect(json["invited_by"]["id"]).to eq(owner.id)
    end

    context "when a pending invite already exists for that user" do
      before { create(:guild_invite, guild: guild, user: invited_user, invited_by: owner) }

      it "returns 422" do
        post "/api/v1/guilds/#{guild.id}/invites",
             params: { invite: { user_id: invited_user.id } },
             headers: auth_headers_with_token(owner),
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "as a non-manager" do
      let(:member_user) do
        u = create(:user)
        u.reload
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end
      before do
        create(:guild_member, guild: guild, user: member_user, role: :member)
        authenticate_api_user(member_user)
      end

      it "returns 403" do
        post "/api/v1/guilds/#{guild.id}/invites",
             params: { invite: { user_id: invited_user.id } },
             headers: auth_headers_with_token(member_user),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/guilds/:guild_id/invites" do
    let!(:invite) { create(:guild_invite, guild: guild, user: invited_user, invited_by: owner) }

    context "as guild owner" do
      before { authenticate_api_user(owner) }

      it "returns the list of invites" do
        get "/api/v1/guilds/#{guild.id}/invites",
            headers: auth_headers_with_token(owner),
            as: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["invites"].length).to eq(1)
        expect(json["invites"].first["id"]).to eq(invite.id)
        expect(json["pagination"]).to include("total_count" => 1)
      end
    end

    context "as a non-manager" do
      before { authenticate_api_user(invited_user) }

      it "returns 403" do
        get "/api/v1/guilds/#{guild.id}/invites",
            headers: auth_headers_with_token(invited_user),
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /api/v1/guilds/:guild_id/invites/:id" do
    let!(:invite) { create(:guild_invite, guild: guild, user: invited_user, invited_by: owner) }

    before { authenticate_api_user(owner) }

    it "rescinds (destroys) the invite and returns 204" do
      expect {
        delete "/api/v1/guilds/#{guild.id}/invites/#{invite.id}",
               headers: auth_headers_with_token(owner),
               as: :json
      }.to change(GuildInvite, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for an unknown invite id" do
      delete "/api/v1/guilds/#{guild.id}/invites/0",
             headers: auth_headers_with_token(owner),
             as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/guild_invites/:id/accept" do
    let!(:invite) { create(:guild_invite, guild: guild, user: invited_user, invited_by: owner) }

    before { authenticate_api_user(invited_user) }

    it "accepts the invite, creates a guild member, and returns 200" do
      expect {
        patch "/api/v1/guild_invites/#{invite.id}/accept",
              headers: auth_headers_with_token(invited_user),
              as: :json
      }.to change(GuildMember, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("accepted")
      expect(invite.reload.accepted?).to be true
      expect(guild.members).to include(invited_user)
    end

    it "returns 422 when the invite is not pending" do
      invite.update!(status: :denied)

      patch "/api/v1/guild_invites/#{invite.id}/accept",
            headers: auth_headers_with_token(invited_user),
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("api.v1.guild_invites.not_pending"))
    end

    it "returns 404 when the invite does not belong to the current user" do
      stranger = create(:user)
      stranger.generate_otp_secret_if_needed unless stranger.otp_secret.present?
      stranger.update!(mfa_enabled: true, mfa_verified: true)
      authenticate_api_user(stranger)

      patch "/api/v1/guild_invites/#{invite.id}/accept",
            headers: auth_headers_with_token(stranger),
            as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/guild_invites/:id/deny" do
    let!(:invite) { create(:guild_invite, guild: guild, user: invited_user, invited_by: owner) }

    before { authenticate_api_user(invited_user) }

    it "denies the invite and returns 200" do
      patch "/api/v1/guild_invites/#{invite.id}/deny",
            headers: auth_headers_with_token(invited_user),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("denied")
      expect(invite.reload.denied?).to be true
    end

    it "returns 422 when the invite is not pending" do
      invite.update!(status: :accepted)

      patch "/api/v1/guild_invites/#{invite.id}/deny",
            headers: auth_headers_with_token(invited_user),
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("api.v1.guild_invites.not_pending"))
    end
  end
end
