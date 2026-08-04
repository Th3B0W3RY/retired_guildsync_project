# frozen_string_literal: true

require "rails_helper"

RSpec.describe "React Roles", type: :request do
  let(:owner) do
    user = create(:user)
    user.update!(auth_method: "discord")
    user
  end

  let(:other_user) do
    user = create(:user)
    user.update!(auth_method: "discord")
    user
  end

  let(:guild)        { create(:guild, owner: owner, discord_id: "1122334455") }
  let!(:synced_role) { create(:discord_role_sync, guild: guild, role_id: "99988877766655", role_name: "Mages") }

  before do
    sign_in owner
  end

  # ──────────────────────────────────────────────────────────────────────────
  # PATCH /guilds/:id/react_roles
  # ──────────────────────────────────────────────────────────────────────────

  describe "PATCH /guilds/:id/react_roles" do
    let(:valid_payload) do
      {
        channel_id: "555444333222111",
        react_roles: [
          { position: 1, role_id: synced_role.role_id, role_name: synced_role.role_name,
            emoji_name: "🔥", emoji_id: "", is_custom_emoji: false }
        ]
      }
    end

    it "creates ReactRole records and returns JSON success" do
      patch guild_react_roles_path(guild),
            params: valid_payload.to_json,
            headers: { "Content-Type" => "application/json", "X-CSRF-Token" => "test" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
      expect(guild.react_roles.count).to eq(1)
      expect(guild.react_roles.first.emoji_name).to eq("🔥")
    end

    it "updates an existing ReactRole record" do
      existing = create(:react_role, guild: guild, position: 1,
                         role_id: synced_role.role_id, emoji_name: "❄️")

      patch guild_react_roles_path(guild),
            params: valid_payload.to_json,
            headers: { "Content-Type" => "application/json", "X-CSRF-Token" => "test" }

      expect(existing.reload.emoji_name).to eq("🔥")
    end

    it "removes positions not included in the payload" do
      create(:react_role, guild: guild, position: 2,
             role_id: synced_role.role_id, emoji_name: "💎")

      patch guild_react_roles_path(guild),
            params: valid_payload.to_json,
            headers: { "Content-Type" => "application/json", "X-CSRF-Token" => "test" }

      expect(guild.react_roles.find_by(position: 2)).to be_nil
    end

    it "ignores slots with no role_id" do
      payload = {
        channel_id: "555444333222111",
        react_roles: [
          { position: 1, role_id: "", emoji_name: "🔥", is_custom_emoji: false }
        ]
      }

      patch guild_react_roles_path(guild),
            params: payload.to_json,
            headers: { "Content-Type" => "application/json", "X-CSRF-Token" => "test" }

      expect(guild.react_roles.count).to eq(0)
    end

    it "rejects role_id that is not a DiscordRoleSync for this guild" do
      payload = valid_payload.deep_dup
      payload[:react_roles][0][:role_id] = "999999999999999999"
      payload[:react_roles][0][:role_name] = "Not Synced"

      expect {
        patch guild_react_roles_path(guild),
              params: payload.to_json,
              headers: { "Content-Type" => "application/json", "X-CSRF-Token" => "test" }
      }.not_to change(ReactRole, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["success"]).to be false
      expect(body["error"].to_s).to include("synced")
    end

    context "authorization" do
      it "returns 404 JSON with localized guild not found for a non-member" do
        sign_in other_user

        patch guild_react_roles_path(guild),
              params: valid_payload.to_json,
              headers: { "Content-Type" => "application/json", "X-CSRF-Token" => "test" }

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("controllers.guilds.not_found"))
      end

      it "returns 403 JSON with localized not authorized for a member without settings permission" do
        create(:guild_member, guild: guild, user: other_user, role: :member, status: :active)
        sign_in other_user

        patch guild_react_roles_path(guild),
              params: valid_payload.to_json,
              headers: { "Content-Type" => "application/json", "X-CSRF-Token" => "test" }

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["error"]).to eq(I18n.t("api.v1.not_authorized"))
      end

      it "returns 401 when not signed in" do
        sign_out owner

        patch guild_react_roles_path(guild),
              params: valid_payload.to_json,
              headers: { "Content-Type" => "application/json", "X-CSRF-Token" => "test" }

        expect(response).to have_http_status(:redirect)
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # POST /guilds/:id/react_roles/deploy
  # ──────────────────────────────────────────────────────────────────────────

  describe "POST /guilds/:id/react_roles/deploy" do
    context "when no react roles are configured" do
      it "redirects to settings with an alert" do
        post guild_react_roles_deploy_path(guild)

        expect(response).to redirect_to(guild_settings_path(guild))
        follow_redirect!
        expect(response.body).to include(I18n.t("controllers.react_roles.no_roles_configured"))
      end
    end

    context "when react roles exist but have no channel" do
      before do
        create(:react_role, guild: guild, position: 1,
               role_id: synced_role.role_id, channel_id: nil)
      end

      it "redirects to settings with an alert" do
        post guild_react_roles_deploy_path(guild)

        expect(response).to redirect_to(guild_settings_path(guild))
        follow_redirect!
        expect(response.body).to include(I18n.t("controllers.react_roles.no_channel_configured"))
      end
    end

    context "when react roles are fully configured" do
      before do
        create(:react_role, guild: guild, position: 1,
               role_id: synced_role.role_id, channel_id: "555666777888")

        stub_request(:post, /discord\.com.*\/messages/)
          .to_return(status: 200, body: { id: "DEPLOYED_MSG_ID" }.to_json,
                     headers: { "Content-Type" => "application/json" })
        stub_request(:put, /discord\.com.*\/reactions\//)
          .to_return(status: 204, body: "")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("test_bot_token")
      end

      it "redirects to settings with a notice" do
        post guild_react_roles_deploy_path(guild)

        expect(response).to redirect_to(guild_settings_path(guild))
        follow_redirect!
        expect(response.body).to include(I18n.t("controllers.react_roles.deployed"))
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # DELETE /guilds/:id/react_roles
  # ──────────────────────────────────────────────────────────────────────────

  describe "DELETE /guilds/:id/react_roles" do
    context "when no react roles exist" do
      it "redirects to settings with a notice" do
        delete guild_react_roles_destroy_path(guild)

        expect(response).to redirect_to(guild_settings_path(guild))
        follow_redirect!
        expect(response.body).to include(I18n.t("controllers.react_roles.removed"))
      end
    end

    context "when react roles exist with a deployed embed" do
      before do
        create(:react_role, :deployed, guild: guild, position: 1,
               role_id: synced_role.role_id, channel_id: "555666777888")

        stub_request(:delete, /discord\.com.*\/messages\//)
          .to_return(status: 204, body: "")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("test_bot_token")
      end

      it "destroys all ReactRole records" do
        expect { delete guild_react_roles_destroy_path(guild) }.to change(ReactRole, :count).by(-1)
      end

      it "redirects to settings with a notice" do
        delete guild_react_roles_destroy_path(guild)

        expect(response).to redirect_to(guild_settings_path(guild))
        follow_redirect!
        expect(response.body).to include(I18n.t("controllers.react_roles.removed"))
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # GET /guilds/:id/react_roles/emojis
  # ──────────────────────────────────────────────────────────────────────────

  describe "GET /guilds/:id/react_roles/emojis" do
    let(:emoji_payload) do
      [{ "id" => "41771983429993937", "name" => "LUL", "animated" => false }]
    end

    before do
      stub_request(:get, /discord\.com.*\/emojis/)
        .to_return(status: 200, body: emoji_payload.to_json,
                   headers: { "Content-Type" => "application/json" })
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("test_bot_token")
    end

    it "returns JSON array of emojis" do
      get guild_react_roles_emojis_path(guild)

      expect(response).to have_http_status(:ok)
      emojis = JSON.parse(response.body)
      expect(emojis).to be_an(Array)
      expect(emojis.first["name"]).to eq("LUL")
    end

    it "returns 401 when not signed in" do
      sign_out owner

      get guild_react_roles_emojis_path(guild)

      expect(response).to have_http_status(:redirect)
    end
  end
end
