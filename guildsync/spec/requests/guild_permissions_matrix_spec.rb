# frozen_string_literal: true

require "rails_helper"

# Maps guild settings checkboxes (role_1..4 + Discord role mapping) to HTTP enforcement.
# Uses stored guild_member.discord_role_id so Discord API is not required (see ApplicationController#user_has_discord_role?).
RSpec.describe "Guild permission matrix (request enforcement)", type: :request do
  # Named "Basic" so `plan_allows?(:activity_feed)` and `:message_center` match `plan_entitlements.yml`
  # (ActivityFeedController and MessageCenterController check plan before role helpers).
  # `guild_documents` / `new` is gated by plan: the documents examples swap the officer to an **Upgraded** subscription.
  let(:pricing_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "basic").first ||
      create(:pricing_plan,
        name: "Basic",
        price: 9,
        price_display: "$9",
        period: "per month",
        max_guilds: 10,
        max_members_per_guild: 100,
        active: true,
        display_order: 91)
  end
  let(:permission_role_id) { "discord-role-perm-matrix-1" }

  def discord_session_user
    u = build(:user, skip_free_plan_subscription: true, auth_method: "discord")
    u.save!
    create(:subscription, user: u, pricing_plan: pricing_plan) unless u.subscriptions.any?
    u
  end

  let(:owner) { discord_session_user }
  let(:guild) { create(:guild, owner: owner) }
  let(:officer) { discord_session_user }

  before do
    create(:guild_member, guild: guild, user: officer, role: :member, status: :active,
      discord_role_id: permission_role_id)
  end

  describe "members list (can_manage_roles? OR can_kick_members?)" do
    it "allows owner" do
      sign_in owner
      get guild_members_list_path(guild)
      expect(response).to have_http_status(:success)
    end

    it "denies member with no matching permission role / flags" do
      sign_in officer
      get guild_members_list_path(guild)
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.members_page_denied"))
    end

    it "allows member when permission slot matches discord_role_id and can_manage_roles" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: true,
        role_1_can_kick_members: false
      )
      sign_in officer
      get guild_members_list_path(guild)
      expect(response).to have_http_status(:success)
    end

    it "denies member when slot matches but can_manage_roles is false (and cannot kick)" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: false
      )
      sign_in officer
      get guild_members_list_path(guild)
      expect(response).to redirect_to(guild_path(guild))
    end

    it "allows member when can_kick_members is true for their slot (no manage_roles)" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: true
      )
      sign_in officer
      get guild_members_list_path(guild)
      expect(response).to have_http_status(:success)
    end
  end

  describe "settings (can_manage_guild_settings?)" do
    it "allows owner" do
      sign_in owner
      get guild_settings_path(guild)
      expect(response).to have_http_status(:success)
    end

    it "denies member without guild-settings permission on their slot" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_guild_settings: false
      )
      sign_in officer
      get guild_settings_path(guild)
      expect(response).to redirect_to(guild_path(guild))
    end

    it "allows member when slot matches and role_1_can_manage_guild_settings" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_guild_settings: true
      )
      sign_in officer
      get guild_settings_path(guild)
      expect(response).to have_http_status(:success)
    end
  end

  describe "invite / applications UI (can_manage_applications?)" do
    it "denies member without applications permission" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_applications: false
      )
      sign_in officer
      get guild_invite_members_path(guild)
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.applications_denied"))
    end

    it "allows member when role_1_can_manage_applications and discord_role_id matches" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_applications: true
      )
      sign_in officer
      get guild_invite_members_path(guild)
      expect(response).to have_http_status(:success)
    end

    it "denies GET review applications without applications permission" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_applications: false
      )
      sign_in officer
      get guild_review_applications_path(guild)
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.applications_denied"))
    end

    it "allows GET review applications when role_1_can_manage_applications and slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_applications: true
      )
      sign_in officer
      get guild_review_applications_path(guild)
      expect(response).to have_http_status(:success)
    end

    it "denies POST create_invite_link without applications permission" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_applications: false
      )
      sign_in officer
      expect {
        post guild_invite_links_path(guild)
      }.not_to(change { guild.reload.guild_invite_links.count })
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.applications_denied"))
    end

    it "allows POST create_invite_link when role matches and under link cap" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_applications: true
      )
      sign_in officer
      expect {
        post guild_invite_links_path(guild)
      }.to change { guild.reload.guild_invite_links.count }.by(1)
      expect(response).to redirect_to(guild_invite_members_path(guild))
      expect(flash[:notice]).to eq(I18n.t("join.invite_link_section"))
    end
  end

  describe "schedule_events (owner-only gate in GuildsController)" do
    it "allows owner" do
      sign_in owner
      get guild_schedule_events_path(guild)
      expect(response).to have_http_status(:success)
    end

    it "denies non-owner even if can_manage_events would be true for their role" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_events: true
      )
      sign_in officer
      get guild_schedule_events_path(guild)
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.owner_only"))
    end
  end

  describe "activity feed (can_view_activity_feed?)" do
    it "denies member without activity-feed permission" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_view_activity_feed: false
      )
      sign_in officer
      get guild_activity_feed_path(guild)
      expect(response).to redirect_to(guild_path(guild))
    end

    it "allows member when role_1_can_view_activity_feed and slot matches" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_view_activity_feed: true
      )
      sign_in officer
      get guild_activity_feed_path(guild)
      expect(response).to have_http_status(:success)
    end
  end

  describe "message center (can_use_message_center?)" do
    it "denies member without message-center permission" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_use_message_center: false
      )
      sign_in officer
      get guild_message_center_path(guild)
      expect(response).to redirect_to(guild_path(guild))
    end

    it "allows member when role_1_can_use_message_center and slot matches" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_use_message_center: true
      )
      sign_in officer
      get guild_message_center_path(guild)
      expect(response).to have_http_status(:success)
    end
  end

  describe "guild warnings index (can_manage_warnings?)" do
    it "denies member without warnings permission on their slot" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_warnings: false
      )
      sign_in officer
      get guild_warnings_path(guild)
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq(I18n.t("guild_warnings.alerts.access_denied"))
    end

    it "allows member when role_1_can_manage_warnings and discord_role_id matches" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_warnings: true
      )
      sign_in officer
      get guild_warnings_path(guild)
      expect(response).to have_http_status(:success)
    end
  end

  describe "members list CSV (can_export_members_csv?)" do
    it "denies CSV when member can open members HTML but export flag is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: true,
        role_1_can_export_members_csv: false
      )
      sign_in officer
      get guild_members_list_path(guild, format: :csv)
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.export_members_csv_denied"))
    end

    it "allows CSV when role_1_can_export_members_csv and slot matches" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: true,
        role_1_can_export_members_csv: true
      )
      sign_in officer
      get guild_members_list_path(guild, format: :csv)
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/csv")
    end
  end

  describe "kick member (can_kick_members?)" do
    let(:peer) { discord_session_user }
    let!(:peer_membership) { create(:guild_member, guild: guild, user: peer, role: :member, status: :active) }

    it "denies DELETE kick when role_1_can_kick_members is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: false
      )
      sign_in officer
      expect {
        delete guild_kick_member_path(guild, peer_membership)
      }.not_to(change { guild.reload.guild_members.exists?(peer_membership.id) })
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.kick_denied"))
    end

    it "allows DELETE kick when role_1_can_kick_members and discord_role_id match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: true
      )
      sign_in officer
      expect {
        delete guild_kick_member_path(guild, peer_membership)
      }.to change { GuildMember.exists?(peer_membership.id) }.from(true).to(false)
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to eq(I18n.t("controllers.guilds.members.kicked"))
    end
  end

  describe "update member role (can_manage_roles?)" do
    let(:peer) { discord_session_user }
    let!(:peer_membership) { create(:guild_member, guild: guild, user: peer, role: :member, status: :active) }
    let(:new_discord_role_id) { "discord-role-matrix-assign-peer" }

    it "denies PATCH when role_1_can_manage_roles is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: false
      )
      sign_in officer
      expect {
        patch guild_update_member_role_path(guild, peer_membership), params: { discord_role_id: new_discord_role_id }
      }.not_to(change { peer_membership.reload.discord_role_id })
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.roles_denied"))
    end

    it "allows PATCH when role_1_can_manage_roles and discord_role_id match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: true,
        role_1_can_kick_members: false
      )
      sign_in officer
      expect {
        patch guild_update_member_role_path(guild, peer_membership), params: { discord_role_id: new_discord_role_id }
      }.to change { peer_membership.reload.discord_role_id }.to(new_discord_role_id)
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to eq(I18n.t("controllers.guilds.members.role_updated"))
    end
  end

  describe "bulk kick members (can_kick_members?)" do
    let(:peer_a) { discord_session_user }
    let(:peer_b) { discord_session_user }
    let!(:membership_a) { create(:guild_member, guild: guild, user: peer_a, role: :member, status: :active) }
    let!(:membership_b) { create(:guild_member, guild: guild, user: peer_b, role: :member, status: :active) }

    it "denies POST when role_1_can_kick_members is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: false
      )
      sign_in officer
      expect {
        post guild_bulk_kick_members_path(guild), params: { member_ids: [ membership_a.id, membership_b.id ] }
      }.not_to(change { guild.reload.guild_members.count })
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.kick_denied"))
    end

    it "allows POST when role_1_can_kick_members and officer slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: true
      )
      sign_in officer
      expect {
        post guild_bulk_kick_members_path(guild), params: { member_ids: [ membership_a.id, membership_b.id ] }
      }.to change { guild.reload.guild_members.count }.by(-2)
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to eq(I18n.t("controllers.guilds.members.bulk_kicked", count: 2))
    end
  end

  describe "bulk update member roles (can_manage_roles?)" do
    let(:peer_a) { discord_session_user }
    let(:peer_b) { discord_session_user }
    let!(:membership_a) { create(:guild_member, guild: guild, user: peer_a, role: :member, status: :active) }
    let!(:membership_b) { create(:guild_member, guild: guild, user: peer_b, role: :member, status: :active) }
    let(:bulk_discord_role_id) { "discord-role-matrix-bulk-update" }

    it "denies POST when role_1_can_manage_roles is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: false
      )
      sign_in officer
      expect {
        post guild_bulk_update_member_roles_path(guild),
          params: { member_ids: [ membership_a.id, membership_b.id ], discord_role_id: bulk_discord_role_id }
      }.not_to(change { [ membership_a.reload.discord_role_id, membership_b.reload.discord_role_id ] })
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.roles_denied"))
    end

    it "allows POST when role_1_can_manage_roles and officer slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: true,
        role_1_can_kick_members: false
      )
      sign_in officer
      post guild_bulk_update_member_roles_path(guild),
        params: { member_ids: [ membership_a.id, membership_b.id ], discord_role_id: bulk_discord_role_id }
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to eq(I18n.t("controllers.guilds.members.bulk_role_updated", count: 2))
      expect(membership_a.reload.discord_role_id).to eq(bulk_discord_role_id)
      expect(membership_b.reload.discord_role_id).to eq(bulk_discord_role_id)
    end
  end

  describe "create member tag (can_manage_tags?)" do
    it "denies create when role_1_can_manage_tags is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_tags: false
      )
      sign_in officer
      expect {
        post guild_create_member_tag_path(guild), params: { name: "MatrixCreateDenied", color: "#223344" }
      }.not_to(change { guild.reload.guild_tags.count })
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.tags_denied"))
    end

    it "allows create when role_1_can_manage_tags and discord_role_id match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_tags: true
      )
      sign_in officer
      expect {
        post guild_create_member_tag_path(guild), params: { name: "MatrixCreateAllowed", color: "#556677" }
      }.to change { guild.reload.guild_tags.where(name: "MatrixCreateAllowed").count }.by(1)
      expect(response).to redirect_to(guild_members_list_path(guild))
    end
  end

  describe "assign member tag (can_manage_tags?)" do
    let(:peer) { discord_session_user }
    let!(:peer_membership) { create(:guild_member, guild: guild, user: peer, role: :member, status: :active) }
    let!(:matrix_guild_tag) do
      GuildTag.create!(guild: guild, name: "MatrixSpecTag", color: "#00aa00", created_by: owner)
    end

    it "denies assign when role_1_can_manage_tags is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_tags: false
      )
      sign_in officer
      expect {
        post guild_assign_member_tag_path(guild, peer_membership, matrix_guild_tag)
      }.not_to change { peer_membership.reload.guild_tags.count }
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.tags_denied"))
    end

    it "allows assign when role_1_can_manage_tags and discord_role_id match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_tags: true
      )
      sign_in officer
      expect {
        post guild_assign_member_tag_path(guild, peer_membership, matrix_guild_tag)
      }.to change { peer_membership.reload.guild_tags.count }.by(1)
      expect(response).to redirect_to(guild_members_list_path(guild))
    end
  end

  describe "remove member tag (can_manage_tags?)" do
    let(:peer) { discord_session_user }
    let!(:peer_membership) { create(:guild_member, guild: guild, user: peer, role: :member, status: :active) }
    let!(:matrix_guild_tag) { GuildTag.create!(guild: guild, name: "MatrixRemoveTag", color: "#00bb00", created_by: owner) }
    let!(:assigned_link) do
      GuildMemberTag.create!(guild_member: peer_membership, guild_tag: matrix_guild_tag, assigned_by: owner)
    end

    it "denies DELETE when role_1_can_manage_tags is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_tags: false
      )
      sign_in officer
      expect {
        delete guild_remove_member_tag_path(guild, peer_membership, matrix_guild_tag)
      }.not_to(change { GuildMemberTag.exists?(assigned_link.id) })
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.tags_denied"))
    end

    it "allows DELETE when role_1_can_manage_tags and discord_role_id match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_tags: true
      )
      sign_in officer
      expect {
        delete guild_remove_member_tag_path(guild, peer_membership, matrix_guild_tag)
      }.to change { GuildMemberTag.exists?(assigned_link.id) }.from(true).to(false)
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to eq(I18n.t("controllers.guilds.members.tags.removed"))
    end
  end

  describe "invite user (can_manage_roles?)" do
    let(:invitee) { discord_session_user }

    before do
      allow_any_instance_of(DiscordService).to receive(:send_dm).and_return(true)
    end

    it "denies POST when role_1_can_manage_roles is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: false
      )
      sign_in officer
      expect {
        post guild_invite_user_path(guild), params: { user_id: invitee.id }
      }.not_to(change { guild.guild_invites.where(status: :pending, user_id: invitee.id).count })
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.invite_denied"))
    end

    it "allows POST when role_1_can_manage_roles and officer slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: true,
        role_1_can_kick_members: false
      )
      sign_in officer
      expect {
        post guild_invite_user_path(guild), params: { user_id: invitee.id }
      }.to change { guild.guild_invites.where(status: :pending, user_id: invitee.id).count }.by(1)
      expect(response).to redirect_to(guild_members_list_path(guild))
      expect(flash[:notice]).to eq(I18n.t("controllers.guilds.invite.success"))
    end
  end

  describe "search users JSON (can_manage_roles?)" do
    let!(:searchable_user) { create(:user, username: "matrix_search_user_unique_ab") }

    it "returns 403 JSON when role_1_can_manage_roles is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: false
      )
      sign_in officer
      get guild_search_users_path(guild), params: { q: searchable_user.username }
      expect(response).to have_http_status(:forbidden)
      body = response.parsed_body
      expect(body["error"]).to eq(I18n.t("controllers.guilds.permissions.roles_denied"))
      expect(body["users"]).to eq([])
    end

    it "returns 200 with matches when role_1_can_manage_roles and officer slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: true,
        role_1_can_kick_members: false
      )
      sign_in officer
      get guild_search_users_path(guild), params: { q: "matrix_search_user_unique_ab" }
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["users"].map { |u| u["id"] }
      expect(ids).to include(searchable_user.id)
    end
  end

  describe "discord roles index JSON (can_manage_roles?)" do
    let(:discord_roles_matrix_guild_id) { "923456789012345671" }
    let!(:matrix_discord_setting_for_roles) do
      create(:guild_discord_setting, guild: guild, discord_guild_id: discord_roles_matrix_guild_id,
        connected_at: Time.current)
    end

    it "returns 403 JSON when role_1_can_manage_roles is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: false,
        role_1_can_kick_members: false
      )
      sign_in officer
      service = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).and_return(service)

      get guild_discord_roles_path(guild), headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq(I18n.t("controllers.guilds.permissions.roles_denied"))
    end

    it "returns 200 when role_1_can_manage_roles and officer slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_roles: true,
        role_1_can_kick_members: false
      )
      sign_in officer
      service = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).and_return(service)
      allow(service).to receive(:get_guild_roles).with(discord_roles_matrix_guild_id).and_return(
        [{ "id" => "role-matrix-1", "name" => "Member" }]
      )

      get guild_discord_roles_path(guild), headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["roles"]).to include(
        hash_including("id" => "role-matrix-1", "synced" => false)
      )
    end
  end

  describe "polls new (can_manage_polls?)" do
    it "denies new poll when role_1_can_manage_polls is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_polls: false
      )
      sign_in officer
      get new_guild_poll_path(guild)
      expect(response).to redirect_to(guild_polls_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.polls.create_denied"))
    end

    it "allows new poll when role_1_can_manage_polls and slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_polls: true
      )
      sign_in officer
      get new_guild_poll_path(guild)
      expect(response).to have_http_status(:success)
    end
  end

  describe "loot rolls new (can_manage_loot_rolls?)" do
    it "denies new loot roll when role_1_can_manage_loot_rolls is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_loot_rolls: false
      )
      sign_in officer
      get new_guild_loot_roll_path(guild)
      expect(response).to redirect_to(guild_loot_rolls_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.loot_rolls.create_denied"))
    end

    it "allows new loot roll when role_1_can_manage_loot_rolls and slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_loot_rolls: true
      )
      sign_in officer
      get new_guild_loot_roll_path(guild)
      expect(response).to have_http_status(:success)
    end
  end

  describe "guild documents new (can_manage_documents?) — officer on Upgraded plan" do
    let(:upgraded_plan) do
      PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
        create(:pricing_plan,
          name: "Upgraded",
          price: 16,
          price_display: "$16",
          period: "per month",
          max_guilds: 10,
          max_members_per_guild: 100,
          active: true,
          display_order: 97)
    end

    before do
      officer.subscriptions.destroy_all
      create(:subscription, user: officer, pricing_plan: upgraded_plan, status: :active, started_at: Time.current)
      officer.reload
    end

    it "denies new document when role_1_can_manage_documents is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_documents: false
      )
      sign_in officer
      get new_guild_document_path(guild)
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guild_documents.manage_denied"))
    end

    it "allows new document when role_1_can_manage_documents and slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_documents: true
      )
      sign_in officer
      get new_guild_document_path(guild)
      expect(response).to have_http_status(:success)
    end
  end

  describe "gear request (can_manage_gear_requests?)" do
    let(:target_peer) { discord_session_user }
    let!(:target_peer_membership) { create(:guild_member, guild: guild, user: target_peer, role: :member, status: :active) }

    it "returns forbidden when role_1_can_manage_gear_requests is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_gear_requests: false
      )
      sign_in officer
      post guild_gear_request_path(guild), params: { user_id: target_peer.id }
      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq(I18n.t("api.v1.not_authorized"))
    end

    it "creates request when role_1_can_manage_gear_requests and slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_gear_requests: true
      )
      allow(DiscordGearRequestJob).to receive(:perform_later)
      sign_in officer
      expect {
        post guild_gear_request_path(guild), params: { user_id: target_peer.id }
      }.to change(GearUploadRequest, :count).by(1)
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
    end
  end

  describe "storage folder create JSON (can_manage_files?)" do
    it "denies folder create when role_1_can_manage_files is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_files: false
      )
      sign_in officer
      post guild_folders_path(guild, format: :json),
        params: { folder: { name: "matrix-files-denied" } },
        headers: { "Accept" => "application/json" }
      expect(response).to redirect_to(guild_storage_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.folders.manage_denied"))
    end

    it "allows folder create when role_1_can_manage_files and slot match" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_files: true
      )
      sign_in officer
      name = "matrix-files-ok-#{SecureRandom.hex(4)}"
      post guild_folders_path(guild, format: :json),
        params: { folder: { name: name } },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body["success"]).to eq(true)
      expect(body.dig("folder", "name")).to eq(name)
    end
  end

  describe "discord events new (can_manage_events? on DiscordEventsController)" do
    it "denies when role_1_can_manage_events is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_events: false
      )
      sign_in officer
      get new_guild_discord_event_path(guild)
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq("You do not have permission to manage Discord events.")
    end

    it "passes permission gate when role_1_can_manage_events is true (may redirect for Discord/bot/channel setup)" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_events: true
      )
      sign_in officer
      get new_guild_discord_event_path(guild)
      expect(flash[:alert].to_s).not_to include("do not have permission to manage Discord events")
    end
  end

  describe "update discord channels (can_manage_discord_channels?)" do
    it "denies PATCH when role_1_can_manage_discord_channels is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_discord_channels: false
      )
      create(:guild_discord_setting, guild: guild) unless guild.reload.guild_discord_setting
      sign_in officer
      patch guild_update_discord_channels_path(guild), params: { events_channel_id: "ch-x" }
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.discord_channels_denied"))
    end

    it "allows PATCH when role_1_can_manage_discord_channels is true and Discord is connected" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_discord_channels: true
      )
      create(:guild_discord_setting, guild: guild) unless guild.reload.guild_discord_setting
      sign_in officer
      patch guild_update_discord_channels_path(guild), params: { events_channel_id: "ch-matrix-ok" }
      expect(response).to redirect_to(guild_settings_path(guild))
      expect(flash[:notice]).to eq(I18n.t("controllers.guilds.discord.channels_updated"))
    end
  end

  describe "GET guild discord connect (DiscordConnectionsController — can_manage_discord_channels?)" do
    before do
      allow_any_instance_of(DiscordService).to receive(:get_guild).and_return({ "id" => "stub-discord-guild" })
    end

    it "denies when role_1_can_manage_discord_channels is false" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_discord_channels: false
      )
      sign_in officer
      get guild_connect_discord_path(guild)
      expect(response).to redirect_to(guild_path(guild))
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.discord_channels_denied"))
    end

    it "allows when role_1_can_manage_discord_channels is true" do
      guild.update!(
        permission_role_1_id: permission_role_id,
        role_1_can_manage_discord_channels: true
      )
      sign_in officer
      get guild_connect_discord_path(guild)
      expect(response).to have_http_status(:success)
    end
  end
end
