# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Discord Roles", type: :request do
  let(:owner) do
    u = build(:user, skip_free_plan_subscription: true, auth_method: "discord")
    u.save!
    create(:subscription, user: u, pricing_plan: create(:pricing_plan, max_guilds: 10, max_members_per_guild: 100)) unless u.subscriptions.any?
    u
  end
  let(:guild) { create(:guild, owner: owner) }
  let(:discord_guild_id) { "123456789012345678" }
  let!(:discord_setting) do
    create(:guild_discord_setting, guild: guild, discord_guild_id: discord_guild_id, connected_at: Time.current)
  end

  before do
    sign_in owner
    set_mfa_verified_in_session
  end

  describe "GET /guilds/:id/discord_roles" do
    it "returns roles with synced status" do
      create(:discord_role_sync, guild: guild, role_id: "role-2", role_name: "Officer")
      service = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).and_return(service)
      allow(service).to receive(:get_guild_roles).with(discord_guild_id).and_return(
        [
          { "id" => "role-1", "name" => "Member" },
          { "id" => "role-2", "name" => "Officer" }
        ]
      )

      get guild_discord_roles_path(guild), headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["roles"]).to include(hash_including("id" => "role-1", "synced" => false))
      expect(body["roles"]).to include(hash_including("id" => "role-2", "synced" => true))
    end

    it "returns 422 with api.discord.not_connected when Discord is not connected" do
      discord_setting.update_column(:connected_at, nil)

      get guild_discord_roles_path(guild), headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("api.discord.not_connected"))
    end
  end

  describe "POST /guilds/:id/discord_roles/sync" do
    it "returns 422 when role_id or role_name is missing" do
      post guild_discord_roles_sync_path(guild),
        params: {},
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("discord_roles.api.role_id_and_name_required"))
    end

    it "returns 201 with discord_roles.api.synced_successfully when creating a new sync" do
      post guild_discord_roles_sync_path(guild),
        params: { role_id: "role-new-sync-spec", role_name: "Spec Role" },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["message"]).to eq(I18n.t("discord_roles.api.synced_successfully"))
      expect(guild.discord_role_syncs.find_by(role_id: "role-new-sync-spec")).to be_present
    end
  end

  describe "access resolution" do
    it "returns 404 JSON when the user is not a member or owner of the guild" do
      stranger = build(:user, skip_free_plan_subscription: true, auth_method: "discord")
      stranger.save!
      create(:subscription, user: stranger, pricing_plan: create(:pricing_plan, max_guilds: 10, max_members_per_guild: 100)) unless stranger.subscriptions.any?
      sign_in stranger
      set_mfa_verified_in_session

      get guild_discord_roles_path(guild), headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.access_denied"))
    end
  end

  describe "POST /guilds/:id/discord_roles/sync_all" do
    it "creates sync records for unsynced Discord roles" do
      create(:discord_role_sync, guild: guild, role_id: "role-1", role_name: "Member")
      service = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).and_return(service)
      allow(service).to receive(:get_guild_roles).with(discord_guild_id).and_return(
        [
          { "id" => "role-1", "name" => "Member" },
          { "id" => "role-2", "name" => "Officer" },
          { "id" => "role-3", "name" => "Raid Lead" }
        ]
      )

      expect do
        post guild_discord_roles_sync_all_path(guild), headers: { "Accept" => "application/json" }
      end.to change { guild.discord_role_syncs.count }.by(2)

      expect(response).to have_http_status(:ok)
      expect(guild.discord_role_syncs.find_by(role_id: "role-2")).to be_present
      expect(guild.discord_role_syncs.find_by(role_id: "role-3")).to be_present
      expect(response.parsed_body["message"]).to eq(I18n.t("discord_roles.api.synced_roles_count", count: 2))
      # Frontend Stimulus controller reads synced_count to render the success toast.
      expect(response.parsed_body["synced_count"]).to eq(2)
    end
  end

  describe "DELETE /guilds/:id/discord_roles/sync/:role_id" do
    it "returns a message string the frontend can display" do
      create(:discord_role_sync, guild: guild, role_id: "role-del", role_name: "Officer")

      delete guild_discord_roles_unsync_path(guild, "role-del"), headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to eq(I18n.t("discord_roles.api.removed_successfully"))
    end
  end

  describe "DELETE /guilds/:id/discord_roles/sync_all" do
    it "returns a message string the frontend can display" do
      create(:discord_role_sync, guild: guild, role_id: "role-bulk", role_name: "Raid")

      delete guild_discord_roles_unsync_all_path(guild), headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to eq(I18n.t("discord_roles.api.removed_syncs_count", count: 1))
    end
  end
end
