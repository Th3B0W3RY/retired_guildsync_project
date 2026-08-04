# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Guild Applications", type: :request do
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

  let(:applicant) do
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

  describe "POST /api/v1/guilds/:guild_id/applications" do
    before { authenticate_api_user(applicant) }

    context "with valid params" do
      it "creates an application and returns 201" do
        expect {
          post "/api/v1/guilds/#{guild.id}/applications",
               params: { application: { discord_username: "applicant#1234", message: "I want to join!" } },
               headers: auth_headers_with_token(applicant),
               as: :json
        }.to change(GuildApplication, :count).by(1)

        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json["status"]).to eq("pending")
        expect(json["discord_username"]).to eq("applicant#1234")
        expect(json["user"]["id"]).to eq(applicant.id)
      end
    end

    context "with missing required fields" do
      it "returns 422" do
        post "/api/v1/guilds/#{guild.id}/applications",
             params: { application: { message: "No username provided" } },
             headers: auth_headers_with_token(applicant),
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["errors"]).to be_present
      end
    end

    context "when a pending application already exists" do
      before { create(:guild_application, guild: guild, user: applicant, status: :pending) }

      it "returns 422" do
        post "/api/v1/guilds/#{guild.id}/applications",
             params: { application: { discord_username: "applicant#1234" } },
             headers: auth_headers_with_token(applicant),
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when the guild does not exist" do
      it "returns 404" do
        post "/api/v1/guilds/0/applications",
             params: { application: { discord_username: "applicant#1234" } },
             headers: auth_headers_with_token(applicant),
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/v1/guilds/:guild_id/applications" do
    let!(:application) { create(:guild_application, guild: guild, user: applicant, status: :pending) }

    context "as guild owner" do
      before { authenticate_api_user(owner) }

      it "returns the list of applications" do
        get "/api/v1/guilds/#{guild.id}/applications",
            headers: auth_headers_with_token(owner),
            as: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["applications"].length).to eq(1)
        expect(json["applications"].first["id"]).to eq(application.id)
        expect(json["pagination"]).to include("total_count" => 1)
      end
    end

    context "as a non-manager" do
      before { authenticate_api_user(applicant) }

      it "returns 403" do
        get "/api/v1/guilds/#{guild.id}/applications",
            headers: auth_headers_with_token(applicant),
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/guilds/:guild_id/applications/:id" do
    let!(:application) { create(:guild_application, guild: guild, user: applicant, status: :pending) }

    context "as guild owner" do
      before { authenticate_api_user(owner) }

      it "returns the application" do
        get "/api/v1/guilds/#{guild.id}/applications/#{application.id}",
            headers: auth_headers_with_token(owner),
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["id"]).to eq(application.id)
      end
    end

    context "as the applicant" do
      before { authenticate_api_user(applicant) }

      it "returns the application" do
        get "/api/v1/guilds/#{guild.id}/applications/#{application.id}",
            headers: auth_headers_with_token(applicant),
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["id"]).to eq(application.id)
      end
    end

    context "as an unrelated user" do
      let(:stranger) do
        u = create(:user)
        u.reload
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end

      before { authenticate_api_user(stranger) }

      it "returns 403" do
        get "/api/v1/guilds/#{guild.id}/applications/#{application.id}",
            headers: auth_headers_with_token(stranger),
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /api/v1/guilds/:guild_id/applications/:id" do
    let!(:application) { create(:guild_application, guild: guild, user: applicant, status: :pending) }

    before { authenticate_api_user(owner) }

    context "accepting an application" do
      it "marks the application as accepted and creates a guild member" do
        expect {
          patch "/api/v1/guilds/#{guild.id}/applications/#{application.id}",
                params: { application: { status: "accepted" } },
                headers: auth_headers_with_token(owner),
                as: :json
        }.to change(GuildMember, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("accepted")
        expect(application.reload.accepted?).to be true
        expect(guild.members).to include(applicant)
      end

      it "returns 422 when the application is not pending" do
        application.update!(status: :rejected)

        patch "/api/v1/guilds/#{guild.id}/applications/#{application.id}",
              params: { application: { status: "accepted" } },
              headers: auth_headers_with_token(owner),
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to eq(I18n.t("api.v1.guild_applications.not_pending"))
      end
    end

    context "rejecting an application" do
      it "marks the application as rejected" do
        patch "/api/v1/guilds/#{guild.id}/applications/#{application.id}",
              params: { application: { status: "rejected" } },
              headers: auth_headers_with_token(owner),
              as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("rejected")
        expect(application.reload.rejected?).to be true
      end
    end

    context "with an invalid status value" do
      it "returns 422" do
        patch "/api/v1/guilds/#{guild.id}/applications/#{application.id}",
              params: { application: { status: "promoted" } },
              headers: auth_headers_with_token(owner),
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to eq(I18n.t("api.v1.guild_applications.invalid_status"))
      end
    end

    context "as a non-manager" do
      before { authenticate_api_user(applicant) }

      it "returns 403" do
        patch "/api/v1/guilds/#{guild.id}/applications/#{application.id}",
              params: { application: { status: "accepted" } },
              headers: auth_headers_with_token(applicant),
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
