# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Events", type: :request do
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
  let(:guild) { create(:guild, owner: user) }

  # Helper to authenticate user for API requests
  # The API BaseController inherits MFA checks from ApplicationController
  # We need to sign in the user and set up MFA verification in the session
  # Session is only available after making a request, so we use set_mfa_verified_in_session
  def authenticate_api_user(user)
    sign_in user
    # Use the helper that makes a request to establish session context
    set_mfa_verified_in_session
  end

  describe "POST /api/v1/guilds/:guild_id/events" do
    before do
      authenticate_api_user(user)
    end

    context "when the user cannot access the guild" do
      let(:stranger) do
        u = create(:user)
        u.reload
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end

      it "returns 404 with access_denied" do
        authenticate_api_user(stranger)
        post "/api/v1/guilds/#{guild.id}/events",
             params: { event: { title: "X", scheduled_at: 1.day.from_now.iso8601 } },
             headers: auth_headers_with_token(stranger),
             as: :json
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      end
    end

    context "with valid attributes" do
      it "creates an event" do
        event_params = {
          event: {
            title: "Raid Event",
            description: "Weekly raid",
            event_type: "raid",
            scheduled_at: 1.day.from_now.iso8601,
            duration: 120
          }
        }

        expect {
          post "/api/v1/guilds/#{guild.id}/events", params: event_params, headers: auth_headers_with_token(user), as: :json
        }.to change(Event, :count).by(1)

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response["title"]).to eq("Raid Event")
        expect(json_response["guild_id"]).to eq(guild.id)
        expect(json_response["created_by_id"]).to eq(user.id)
      end
    end

    context "with invalid attributes" do
      it "validates required fields" do
        event_params = {
          event: {
            title: "AB", # too short
            scheduled_at: nil # required
          }
        }

        post "/api/v1/guilds/#{guild.id}/events", params: event_params, headers: auth_headers_with_token(user), as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /api/v1/guilds/:guild_id/events" do
    let!(:event1) { create(:event, guild: guild, scheduled_at: 1.day.from_now) }
    let!(:event2) { create(:event, guild: guild, scheduled_at: 2.days.from_now) }

    before do
      authenticate_api_user(user)
      set_mfa_verified_in_session
    end

    it "returns 404 when the user cannot access the guild" do
      stranger = create(:user)
      stranger.reload
      stranger.generate_otp_secret_if_needed unless stranger.otp_secret.present?
      stranger.update!(mfa_enabled: true, mfa_verified: true)
      authenticate_api_user(stranger)

      get "/api/v1/guilds/#{guild.id}/events", headers: auth_headers_with_token(stranger), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "lists events for a guild" do
      get "/api/v1/guilds/#{guild.id}/events", headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["events"].length).to eq(2)
      expect(json_response["pagination"]).to include(
        "page" => 1,
        "per_page" => 25,
        "total_count" => 2,
        "total_pages" => 1
      )
    end

    it "supports page and per_page for events list" do
      get "/api/v1/guilds/#{guild.id}/events", params: { page: 2, per_page: 1 }, headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["events"].length).to eq(1)
      expect(json_response["pagination"]).to include(
        "page" => 2,
        "per_page" => 1,
        "total_count" => 2,
        "total_pages" => 2
      )
    end
  end

  describe "GET /api/v1/events/:id" do
    let!(:event) { create(:event, guild: guild, scheduled_at: 1.day.from_now) }

    before do
      authenticate_api_user(user)
      set_mfa_verified_in_session
    end

    it "shows a specific event" do
      get "/api/v1/events/#{event.id}", headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["id"]).to eq(event.id)
      expect(json_response["title"]).to eq(event.title)
    end

    it "returns 404 for a user who cannot access the event's guild (no existence leak)" do
      outsider = create(:user)
      outsider.reload
      outsider.generate_otp_secret_if_needed unless outsider.otp_secret.present?
      outsider.update!(mfa_enabled: true, mfa_verified: true)
      authenticate_api_user(outsider)

      get "/api/v1/events/#{event.id}", headers: auth_headers_with_token(outsider), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "returns 404 for an unknown event id" do
      get "/api/v1/events/0", headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "returns 404 for an inactive guild member" do
      inactive_user = create(:user)
      inactive_user.reload
      inactive_user.generate_otp_secret_if_needed unless inactive_user.otp_secret.present?
      inactive_user.update!(mfa_enabled: true, mfa_verified: true)
      create(:guild_member, guild: guild, user: inactive_user, role: :member, status: :inactive)
      authenticate_api_user(inactive_user)

      get "/api/v1/events/#{event.id}", headers: auth_headers_with_token(inactive_user), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "PATCH /api/v1/events/:id" do
    let!(:event) { create(:event, guild: guild, title: "Original Title") }

    before do
      authenticate_api_user(user)
      set_mfa_verified_in_session
    end

    it "updates event information" do
      update_params = {
        event: {
          title: "Updated Title",
          description: "Updated description"
        }
      }

      patch "/api/v1/events/#{event.id}", params: update_params, headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:ok)
      event.reload
      expect(event.title).to eq("Updated Title")
    end

    it "returns 404 when the user cannot access the event's guild" do
      outsider = create(:user)
      outsider.reload
      outsider.generate_otp_secret_if_needed unless outsider.otp_secret.present?
      outsider.update!(mfa_enabled: true, mfa_verified: true)
      authenticate_api_user(outsider)

      patch "/api/v1/events/#{event.id}",
            params: { event: { title: "Hax" } },
            headers: auth_headers_with_token(outsider),
            as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      expect(event.reload.title).to eq("Original Title")
    end

    it "updates event status" do
      update_params = {
        event: {
          status: "in_progress"
        }
      }

      patch "/api/v1/events/#{event.id}", params: update_params, headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:ok)
      event.reload
      expect(event.status).to eq("in_progress")
    end
  end

  describe "DELETE /api/v1/events/:id" do
    let!(:event) { create(:event, guild: guild) }

    before do
      authenticate_api_user(user)
      set_mfa_verified_in_session
    end

    it "deletes an event" do
      expect {
        delete "/api/v1/events/#{event.id}", headers: auth_headers_with_token(user), as: :json
      }.to change(Event, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /api/v1/events/:id/participate" do
    let!(:event) { create(:event, guild: guild) }
    let(:participant) do
      u = create(:user)
      u.reload
      u.generate_otp_secret_if_needed unless u.otp_secret.present?
      u.update!(mfa_enabled: true, mfa_verified: true)
      u
    end
    let!(:participant_membership) do
      create(:guild_member, guild: guild, user: participant, role: :member, status: :active)
    end

    before do
      authenticate_api_user(participant)
      set_mfa_verified_in_session
    end

    it "allows user to participate in event" do
      participation_params = {
        status: "attending",
        notes: "Will be there!"
      }

      expect {
        post "/api/v1/events/#{event.id}/participate", params: participation_params, headers: auth_headers_with_token(participant), as: :json
      }.to change(EventParticipation, :count).by(1)

      expect(response).to have_http_status(:ok)
      participation = EventParticipation.find_by(event: event, user: participant)
      expect(participation.status).to eq("attending")
      expect(participation.notes).to eq("Will be there!")
    end
  end

  describe "GET /api/v1/events/:id/participants" do
    let!(:event) { create(:event, guild: guild) }
    let(:participant) { create(:user) }

    before do
      authenticate_api_user(user)
      set_mfa_verified_in_session
    end

    it "lists event participants" do
      create(:event_participation, event: event, user: participant, status: :attending)

      get "/api/v1/events/#{event.id}/participants", headers: auth_headers_with_token(user), as: :json
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["participants"].length).to eq(1)
      expect(json_response["participants"].first["user_id"]).to eq(participant.id)
      expect(json_response["pagination"]).to include(
        "page" => 1,
        "per_page" => 25,
        "total_count" => 1,
        "total_pages" => 1
      )
    end
  end

  describe "DELETE /api/v1/events/:id/participate" do
    let!(:event) { create(:event, guild: guild) }
    let(:participant) do
      u = create(:user)
      u.reload
      u.generate_otp_secret_if_needed unless u.otp_secret.present?
      u.update!(mfa_enabled: true, mfa_verified: true)
      u
    end
    let!(:participant_membership) { create(:guild_member, guild: guild, user: participant, role: :member, status: :active) }

    before do
      authenticate_api_user(participant)
      set_mfa_verified_in_session
    end

    context "when the user has an existing participation" do
      let!(:participation) { create(:event_participation, event: event, user: participant, status: :attending) }

      it "removes the participation and returns 204" do
        expect {
          delete "/api/v1/events/#{event.id}/participate", headers: auth_headers_with_token(participant), as: :json
        }.to change(EventParticipation, :count).by(-1)

        expect(response).to have_http_status(:no_content)
        expect(EventParticipation.exists?(participation.id)).to be false
      end
    end

    context "when the user is not participating" do
      it "returns 404 with not_participating error" do
        delete "/api/v1/events/#{event.id}/participate", headers: auth_headers_with_token(participant), as: :json
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("api.v1.not_participating"))
      end
    end

    context "when the user cannot access the event's guild" do
      let(:outsider) do
        u = create(:user)
        u.reload
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end

      it "returns 404 with access_denied" do
        authenticate_api_user(outsider)
        delete "/api/v1/events/#{event.id}/participate", headers: auth_headers_with_token(outsider), as: :json
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      end
    end
  end
end

