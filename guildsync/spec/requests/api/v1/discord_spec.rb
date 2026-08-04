# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Discord", type: :request do
  let(:user) do
    u = create(:user)
    u.generate_otp_secret_if_needed unless u.otp_secret.present?
    u.update!(mfa_enabled: true, mfa_verified: true)
    u
  end
  let(:guild) { create(:guild, owner: user) }
  let!(:discord_setting) { create(:guild_discord_setting, guild: guild) }

  def authenticate_api_user(user)
    sign_in user
    set_mfa_verified_in_session
  end

  describe "GET /api/v1/guilds/:guild_id/discord/channels" do
    before do
      authenticate_api_user(user)
    end

    it "returns paginated text channels only" do
      discord_service = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).and_return(discord_service)
      allow(discord_service).to receive(:get_guild_channels).and_return(
        [
          { "id" => "20", "name" => "voice", "type" => 2, "position" => 1 },
          { "id" => "10", "name" => "general", "type" => 0, "position" => 0 },
          { "id" => "11", "name" => "raids", "type" => 0, "position" => 1 }
        ]
      )

      get "/api/v1/guilds/#{guild.id}/discord/channels",
          params: { page: 2, per_page: 1 },
          headers: auth_headers_with_token(user),
          as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["channels"].length).to eq(1)
      expect(json_response["channels"].first["id"]).to eq("11")
      expect(json_response["pagination"]).to include(
        "page" => 2,
        "per_page" => 1,
        "total_count" => 2,
        "total_pages" => 2
      )
    end

    context "when Discord is not connected for the guild" do
      it "returns 422 with api.discord.not_connected" do
        prior = discord_setting.connected_at
        discord_setting.update_column(:connected_at, nil)

        get "/api/v1/guilds/#{guild.id}/discord/channels",
            headers: auth_headers_with_token(user),
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to eq(I18n.t("api.discord.not_connected"))
      ensure
        discord_setting.update_column(:connected_at, prior) if prior.present?
      end
    end

    context "when a guild member has can_manage_discord_channels via role slot" do
      let(:slot_id) { "api_v1_discord_channels_slot" }
      let(:officer) do
        u = create(:user)
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end
      let!(:officer_member) do
        create(:guild_member, guild: guild, user: officer, role: :member, status: :active, discord_role_id: slot_id)
      end

      before do
        guild.update!(permission_role_1_id: slot_id, role_1_can_manage_discord_channels: true)
        authenticate_api_user(officer)
      end

      it "returns 200" do
        discord_service = instance_double(DiscordService)
        allow(DiscordService).to receive(:new).and_return(discord_service)
        allow(discord_service).to receive(:get_guild_channels).and_return(
          [ { "id" => "10", "name" => "general", "type" => 0, "position" => 0 } ]
        )

        get "/api/v1/guilds/#{guild.id}/discord/channels",
            headers: auth_headers_with_token(officer),
            as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context "when the member matches the slot but can_manage_discord_channels is false" do
      let(:slot_id) { "api_v1_discord_channels_slot_denied" }
      let(:officer) do
        u = create(:user)
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end
      let!(:officer_member) do
        create(:guild_member, guild: guild, user: officer, role: :member, status: :active, discord_role_id: slot_id)
      end

      before do
        guild.update!(permission_role_1_id: slot_id, role_1_can_manage_discord_channels: false)
        authenticate_api_user(officer)
      end

      it "returns 403" do
        get "/api/v1/guilds/#{guild.id}/discord/channels",
            headers: auth_headers_with_token(officer),
            as: :json

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("api.v1.not_authorized"))
      end
    end

    context "when the user has no access to the guild" do
      let(:stranger) do
        u = create(:user)
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end

      before { authenticate_api_user(stranger) }

      it "returns 404 with access_denied" do
        get "/api/v1/guilds/#{guild.id}/discord/channels",
            headers: auth_headers_with_token(stranger),
            as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      end
    end
  end

  describe "PATCH /api/v1/guilds/:guild_id/discord/channels" do
    before do
      authenticate_api_user(user)
    end

    it "updates channel ids when the owner is authorized" do
      patch "/api/v1/guilds/#{guild.id}/discord/channels",
            params: { channels: { events_channel_id: "evt_ch_api_patch_owner" } },
            headers: auth_headers_with_token(user),
            as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["message"]).to eq(I18n.t("api.discord.channels_updated"))
      expect(body.dig("settings", "events_channel_id")).to eq("evt_ch_api_patch_owner")
      expect(discord_setting.reload.events_channel_id).to eq("evt_ch_api_patch_owner")
    end

    context "when a guild member has can_manage_discord_channels via role slot" do
      let(:slot_id) { "api_v1_discord_patch_slot" }
      let(:officer) do
        u = create(:user)
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end
      let!(:officer_member) do
        create(:guild_member, guild: guild, user: officer, role: :member, status: :active, discord_role_id: slot_id)
      end

      before do
        guild.update!(permission_role_1_id: slot_id, role_1_can_manage_discord_channels: true)
        authenticate_api_user(officer)
      end

      it "returns 200 and persists settings" do
        patch "/api/v1/guilds/#{guild.id}/discord/channels",
              params: { channels: { gear_channel_id: "gear_ch_api_patch_ok" } },
              headers: auth_headers_with_token(officer),
              as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).dig("settings", "gear_channel_id")).to eq("gear_ch_api_patch_ok")
        expect(discord_setting.reload.gear_channel_id).to eq("gear_ch_api_patch_ok")
      end
    end

    context "when the member matches the slot but can_manage_discord_channels is false" do
      let(:slot_id) { "api_v1_discord_patch_slot_denied" }
      let(:officer) do
        u = create(:user)
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end
      let!(:officer_member) do
        create(:guild_member, guild: guild, user: officer, role: :member, status: :active, discord_role_id: slot_id)
      end

      before do
        guild.update!(permission_role_1_id: slot_id, role_1_can_manage_discord_channels: false)
        authenticate_api_user(officer)
      end

      it "returns 403 and does not change settings" do
        prior = discord_setting.reload.gear_channel_id

        patch "/api/v1/guilds/#{guild.id}/discord/channels",
              params: { channels: { gear_channel_id: "gear_ch_should_not_save" } },
              headers: auth_headers_with_token(officer),
              as: :json

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("api.v1.not_authorized"))
        expect(discord_setting.reload.gear_channel_id).to eq(prior)
      end
    end

    context "when the user has no access to the guild" do
      let(:stranger) do
        u = create(:user)
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end

      before { authenticate_api_user(stranger) }

      it "returns 404 with access_denied" do
        patch "/api/v1/guilds/#{guild.id}/discord/channels",
              params: { channels: { gear_channel_id: "should_not_apply" } },
              headers: auth_headers_with_token(stranger),
              as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      end
    end
  end

  describe "POST /api/v1/guilds/:guild_id/discord/events/:event_id/signup" do
    let(:event) { create(:event, guild: guild, created_by: user) }

    before do
      allow(DiscordUpdateEventParticipantsJob).to receive(:perform_later)
    end

    context "when the caller is an active member without can_manage_discord_channels" do
      let(:member_user) do
        u = create(:user)
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end
      let!(:plain_member) do
        create(:guild_member, guild: guild, user: member_user, role: :member, status: :active)
      end

      before do
        authenticate_api_user(member_user)
      end

      it "returns 200 and records participation" do
        expect do
          post "/api/v1/guilds/#{guild.id}/discord/events/#{event.id}/signup",
               params: { discord_user_id: "discord_uid_api_signup", discord_username: "ApiSignupUser" },
               headers: auth_headers_with_token(member_user),
               as: :json
        end.to change { event.reload.discord_event_participations.count }.by(1)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["message"]).to eq(I18n.t("api.discord.signup_success"))
        expect(DiscordUpdateEventParticipantsJob).to have_received(:perform_later).with(event.id)
      end

      it "returns 422 when discord_user_id or discord_username is missing" do
        post "/api/v1/guilds/#{guild.id}/discord/events/#{event.id}/signup",
             params: { discord_user_id: "only_one_field" },
             headers: auth_headers_with_token(member_user),
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to eq(I18n.t("api.discord.missing_discord_identity"))
      end

      it "returns 404 when the event id does not exist in the guild" do
        post "/api/v1/guilds/#{guild.id}/discord/events/0/signup",
             params: { discord_user_id: "discord_uid_missing_evt", discord_username: "NoEvent" },
             headers: auth_headers_with_token(member_user),
             as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("api.discord.event_not_found"))
      end
    end

    context "when the caller is not a guild member" do
      let(:stranger) do
        u = create(:user)
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end

      before { authenticate_api_user(stranger) }

      it "returns 404 with access_denied (no guild id leak)" do
        post "/api/v1/guilds/#{guild.id}/discord/events/#{event.id}/signup",
             params: { discord_user_id: "discord_uid_stranger", discord_username: "Stranger" },
             headers: auth_headers_with_token(stranger),
             as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
      end
    end

    context "when the caller is an inactive member" do
      let(:lapsed) do
        u = create(:user)
        u.generate_otp_secret_if_needed unless u.otp_secret.present?
        u.update!(mfa_enabled: true, mfa_verified: true)
        u
      end
      let!(:lapsed_member) do
        create(:guild_member, guild: guild, user: lapsed, role: :member, status: :inactive)
      end

      before { authenticate_api_user(lapsed) }

      it "returns 403 with not_authorized" do
        post "/api/v1/guilds/#{guild.id}/discord/events/#{event.id}/signup",
             params: { discord_user_id: "discord_uid_inactive", discord_username: "Inactive" },
             headers: auth_headers_with_token(lapsed),
             as: :json

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to eq(I18n.t("api.v1.not_authorized"))
      end
    end
  end
end
