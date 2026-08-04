# frozen_string_literal: true

require "rails_helper"

# Exhaustive HTTP-level checks for the Role Permissions checkboxes × Discord role slots 1–4.
# Uses guild_member.discord_role_id + permission_role_{n}_id (no live Discord API).
#
# Historical permission-enforcement notes live in guildsync_knowledge_base.
# for product/code mismatches (owner-only routes vs settings UI).
RSpec.describe "Guild role permissions grid (19 permissions × 4 slots)", type: :request do
  # Tier name must match `config/plan_entitlements.yml` so plan gates align with role checks:
  # `activity_feed`, `warnings`, `message_center`, `guild_documents`, `file_storage`, `ai_gear_scanner`, etc.
  let(:pricing_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
      create(:pricing_plan,
        name: "Upgraded",
        price: 16,
        price_display: "$16",
        period: "per month",
        max_guilds: nil,
        max_members_per_guild: nil,
        active: true,
        display_order: 97)
  end

  def discord_user_with_plan
    u = build(:user, skip_free_plan_subscription: true, auth_method: "discord")
    u.save!
    create(:subscription, user: u, pricing_plan: pricing_plan) if u.subscriptions.none?
    u
  end

  let(:owner) { discord_user_with_plan }
  let(:guild) { create(:guild, owner: owner) }
  let(:officer) { discord_user_with_plan }
  let(:perm_discord_role_id) { "discord-role-grid-spec" }

  let!(:officer_membership) do
    create(:guild_member, guild: guild, user: officer, role: :member, status: :active,
      discord_role_id: perm_discord_role_id)
  end

  # Every boolean flag name suffix (matches Guild columns role_{n}_*)
  FLAG_SUFFIXES = %w[
    can_manage_roles can_manage_applications can_manage_guild_settings can_kick_members
    can_invite_alliance_guilds can_kick_alliance_guilds can_manage_tags can_manage_warnings
    can_manage_documents can_manage_files can_manage_events can_manage_polls can_manage_loot_rolls
    can_manage_discord_channels can_view_activity_feed can_export_members_csv can_use_message_center
    can_manage_gear_requests can_edit_gear_scanned_stats
  ].freeze

  def clear_all_permission_flags!(g)
    attrs = {}
    (1..4).each do |n|
      FLAG_SUFFIXES.each { |s| attrs[:"role_#{n}_#{s}"] = false }
    end
    g.update!(attrs)
  end

  # Map only `slot` to officer's Discord role; other slots get non-matching IDs.
  def bind_slot!(g, slot)
    attrs = {}
    (1..4).each do |n|
      attrs[:"permission_role_#{n}_id"] = (n == slot) ? perm_discord_role_id : "foreign-role-#{n}-#{g.id}"
    end
    g.update!(attrs)
  end

  def apply_slot_and_flag!(g, slot, flag_suffix, enabled:)
    clear_all_permission_flags!(g)
    bind_slot!(g, slot)
    g.update!(:"role_#{slot}_#{flag_suffix}" => enabled)
  end

  # Multiple flags on the same slot (e.g. CSV export needs members page access + export toggle).
  def apply_slot_flags!(g, slot, suffix_to_enabled)
    clear_all_permission_flags!(g)
    bind_slot!(g, slot)
    attrs = suffix_to_enabled.transform_keys { |suffix| :"role_#{slot}_#{suffix}" }
    g.update!(attrs)
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:mfa_verified_for_session?).and_return(true)
  end

  shared_examples "permission allow/deny for slot" do |flag_suffix:, slot:, allow_request:, deny_assert:, allow_assert:|
    context "slot #{slot} flag #{flag_suffix}" do
      before { sign_in officer }

      it "denies when the flag is false" do
        apply_slot_and_flag!(guild, slot, flag_suffix, enabled: false)
        instance_exec(&allow_request)
        instance_exec(response, guild, &deny_assert)
      end

      it "allows when the flag is true" do
        apply_slot_and_flag!(guild, slot, flag_suffix, enabled: true)
        instance_exec(&allow_request)
        instance_exec(response, guild, &allow_assert)
      end
    end
  end

  (1..4).each do |slot|
    describe "slot #{slot}" do
      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_roles",
        slot: slot,
        allow_request: -> { get guild_members_list_path(guild) },
        deny_assert: ->(res, g) {
          expect(res).to redirect_to(guild_path(g))
          expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.members_page_denied"))
        },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_applications",
        slot: slot,
        allow_request: -> { get guild_invite_members_path(guild) },
        deny_assert: ->(res, g) {
          expect(res).to redirect_to(guild_path(g))
          expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.applications_denied"))
        },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_guild_settings",
        slot: slot,
        allow_request: -> { get guild_settings_path(guild) },
        deny_assert: ->(res, g) { expect(res).to redirect_to(guild_path(g)) },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_kick_members",
        slot: slot,
        allow_request: -> { get guild_members_list_path(guild) },
        deny_assert: ->(res, g) {
          expect(res).to redirect_to(guild_path(g))
          expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.members_page_denied"))
        },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_tags",
        slot: slot,
        allow_request: lambda {
          tag = guild.guild_tags.create!(name: "GridTag#{slot}", color: "#111111", created_by: owner)
          post guild_assign_member_tag_path(guild, officer_membership, tag)
        },
        deny_assert: ->(res, g) {
          expect(res).to redirect_to(guild_members_list_path(g))
          expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.tags_denied", default: "You do not have permission to manage tags."))
        },
        allow_assert: ->(res, g) {
          expect(res).to redirect_to(guild_members_list_path(g))
          expect(flash[:notice]).to be_present
        }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_warnings",
        slot: slot,
        allow_request: -> { get guild_warnings_path(guild) },
        deny_assert: ->(res, g) {
          expect(res).to redirect_to(guild_path(g))
        },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_documents",
        slot: slot,
        allow_request: -> { get new_guild_document_path(guild) },
        deny_assert: ->(res, g) { expect(res).to redirect_to(guild_path(g)) },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_files",
        slot: slot,
        allow_request: lambda {
          post guild_folders_path(guild, format: :json),
            params: { folder: { name: "perm-grid-folder-#{slot}-#{SecureRandom.hex(4)}" } },
            headers: { "Accept" => "application/json" }
        },
        deny_assert: ->(res, g) {
          expect(res).to redirect_to(guild_storage_path(g))
        },
        allow_assert: ->(res, _g) {
          expect(res).to have_http_status(:success)
          body = JSON.parse(res.body)
          expect(body["success"]).to eq(true)
          expect(body.dig("folder", "id")).to be_present
        }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_polls",
        slot: slot,
        allow_request: -> { get new_guild_poll_path(guild) },
        deny_assert: ->(res, g) { expect(res).to redirect_to(guild_polls_path(g)) },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_loot_rolls",
        slot: slot,
        allow_request: -> { get new_guild_loot_roll_path(guild) },
        deny_assert: ->(res, g) { expect(res).to redirect_to(guild_loot_rolls_path(g)) },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_view_activity_feed",
        slot: slot,
        allow_request: -> { get guild_activity_feed_path(guild) },
        deny_assert: ->(res, g) { expect(res).to redirect_to(guild_path(g)) },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      describe "can_export_members_csv (requires members page access)" do
        before { sign_in officer }

        it "denies CSV when export false but member can open members HTML (slot #{slot})" do
          apply_slot_flags!(guild, slot, "can_manage_roles" => true, "can_export_members_csv" => false)
          get guild_members_list_path(guild, format: :csv)
          expect(response).to redirect_to(guild_members_list_path(guild))
        end

        it "allows CSV when export true (slot #{slot})" do
          apply_slot_flags!(guild, slot, "can_manage_roles" => true, "can_export_members_csv" => true)
          get guild_members_list_path(guild, format: :csv)
          expect(response).to have_http_status(:success)
          expect(response.media_type).to eq("text/csv")
        end
      end

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_use_message_center",
        slot: slot,
        allow_request: -> { get guild_message_center_path(guild) },
        deny_assert: ->(res, g) { expect(res).to redirect_to(guild_path(g)) },
        allow_assert: ->(res, _g) { expect(res).to have_http_status(:success) }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_gear_requests",
        slot: slot,
        allow_request: -> { post guild_gear_request_path(guild), params: { user_id: owner.id } },
        deny_assert: ->(res, _g) {
          expect(res).to have_http_status(:forbidden)
        },
        allow_assert: ->(res, _g) {
          expect(res).to have_http_status(:success).or have_http_status(:unprocessable_entity)
          body = JSON.parse(res.body) rescue {}
          expect(body["error"]).not_to eq(I18n.t("api.v1.not_authorized"))
        }

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_edit_gear_scanned_stats",
        slot: slot,
        allow_request: lambda {
          GearSnapshot.where(guild_id: guild.id, user_id: owner.id).delete_all
          create(:gear_snapshot,
            guild: guild,
            user: owner,
            game: guild.games.first,
            data: { "GridStat" => "1" })
          patch guild_member_stats_fields_path(guild, user_id: owner.id),
            params: { op: "remove", stat_key: "GridStat" },
            as: :json
        },
        deny_assert: ->(res, _g) {
          expect(res).to have_http_status(:forbidden)
        },
        allow_assert: ->(res, _g) {
          expect(res).to have_http_status(:ok)
          body = res.parsed_body
          expect(body["ok"]).to eq(true)
        }

      describe "can_manage_events (Discord events — not schedule_events page)" do
        before { sign_in officer }

        it "denies new discord event when flag false (slot #{slot})" do
          apply_slot_and_flag!(guild, slot, "can_manage_events", enabled: false)
          get new_guild_discord_event_path(guild)
          expect(response).to redirect_to(guild_path(guild))
          expect(flash[:alert]).to include("permission")
        end

        it "passes permission gate when flag true (slot #{slot}); may redirect for Discord/bot setup" do
          apply_slot_and_flag!(guild, slot, "can_manage_events", enabled: true)
          get new_guild_discord_event_path(guild)
          expect(flash[:alert]).not_to include("do not have permission to manage Discord events")
          if response.redirect?
            expect(response.location).not_to eq(guild_url(guild))
          else
            expect(response).to have_http_status(:success)
          end
        end
      end

      include_examples "permission allow/deny for slot",
        flag_suffix: "can_manage_discord_channels",
        slot: slot,
        allow_request: lambda {
          create(:guild_discord_setting, guild: guild) unless guild.reload.guild_discord_setting
          patch guild_update_discord_channels_path(guild),
            params: { events_channel_id: "grid-ch-#{slot}-#{SecureRandom.hex(3)}" }
        },
        deny_assert: ->(res, g) {
          expect(res).to redirect_to(guild_path(g))
          expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.discord_channels_denied"))
        },
        allow_assert: ->(res, _g) {
          expect(res).to redirect_to(guild_settings_path(guild))
          expect(flash[:notice]).to eq(I18n.t("controllers.guilds.discord.channels_updated"))
        }
    end
  end

  describe "schedule_events page remains owner-only (not gated by can_manage_events)" do
    (1..4).each do |slot|
      it "slot #{slot}: officer with can_manage_events cannot open schedule_events" do
        apply_slot_and_flag!(guild, slot, "can_manage_events", enabled: true)
        sign_in officer
        get guild_schedule_events_path(guild)
        expect(response).to redirect_to(guild_path(guild))
        expect(flash[:alert]).to eq(I18n.t("controllers.guilds.permissions.owner_only"))
      end
    end
  end

  describe "alliance invite permission via alliance_invites#create (all slots)" do
    let(:alliance) { create(:alliance, leader_guild: guild, leader_user: owner) }

    before do
      create(:alliance_guild, alliance: alliance, guild: guild, status: :active)
      AllianceMemberSyncService.new(alliance, guild).sync!
    end

    (1..4).each do |slot|
      it "slot #{slot}: denies create without invite flag" do
        other_owner = discord_user_with_plan
        target = create(:guild, owner: other_owner, publicly_listed: true)
        apply_slot_and_flag!(guild, slot, "can_invite_alliance_guilds", enabled: false)
        sign_in officer
        post alliance_alliance_invites_path(alliance), params: { guild_id: target.id }
        expect(response).to redirect_to(alliance_path(alliance))
        expect(flash[:alert]).to eq(I18n.t("alliances.invites.errors.invite_unauthorized"))
      end

      it "slot #{slot}: allows create with invite flag" do
        other_owner = discord_user_with_plan
        target = create(:guild, owner: other_owner, publicly_listed: true)
        apply_slot_and_flag!(guild, slot, "can_invite_alliance_guilds", enabled: true)
        sign_in officer
        expect do
          post alliance_alliance_invites_path(alliance), params: { guild_id: target.id }
        end.to change { AllianceInvite.where(alliance_id: alliance.id, guild_id: target.id).count }.by(1)
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "alliance kick permission via alliances#kick_guild (all slots)" do
    let(:other_guild_owner) { discord_user_with_plan }
    let(:other_guild) { create(:guild, owner: other_guild_owner) }
    let(:alliance) { create(:alliance, leader_guild: guild, leader_user: owner) }

    before do
      create(:alliance_guild, alliance: alliance, guild: guild, status: :active)
      create(:alliance_guild, alliance: alliance, guild: other_guild, status: :active, joined_at: Time.current)
      AllianceMemberSyncService.new(alliance, guild).sync!
      AllianceMemberSyncService.new(alliance, other_guild).sync!
    end

    (1..4).each do |slot|
      it "slot #{slot}: denies kick without kick flag" do
        apply_slot_and_flag!(guild, slot, "can_kick_alliance_guilds", enabled: false)
        sign_in officer
        post kick_guild_alliance_path(alliance), params: { guild_id: other_guild.id }
        expect(response).to redirect_to(alliance_path(alliance))
        expect(flash[:alert]).to eq(I18n.t("alliances.errors.kick_unauthorized"))
      end

      it "slot #{slot}: allows kick with kick flag" do
        apply_slot_and_flag!(guild, slot, "can_kick_alliance_guilds", enabled: true)
        sign_in officer
        post kick_guild_alliance_path(alliance), params: { guild_id: other_guild.id }
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to be_blank
      end
    end
  end
end
