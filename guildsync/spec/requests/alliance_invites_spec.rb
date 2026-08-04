# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AllianceInvites", type: :request do
  let(:active_paid_plan) do
    plan = PricingPlan.find_or_create_by!(name: "RSpec Alliance Invites Paid") do |p|
      p.price = 19
      p.price_display = "$19"
      p.period = "per month"
      p.max_guilds = 10
      p.max_members_per_guild = 100
      p.active = true
      p.display_order = 52
      p.can_create_alliance = true
    end
    plan.update!(can_create_alliance: true) unless plan.can_create_alliance?
    plan
  end

  let(:owner) do
    u = create(:user, :discord_auth, skip_free_plan_subscription: true)
    create(:subscription, user: u, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
    u
  end
  let(:guild) { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end

  let(:target_guild) { create(:guild) }
  let(:custom_manager_user) do
    u = create(:user, :discord_auth, skip_free_plan_subscription: true)
    create(:subscription, user: u, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
    u
  end

  before { sign_in owner }

  describe "GET /alliances/:alliance_id/alliance_invites/guild_search" do
    let!(:listed_guild) { create(:guild, name: "ZetaPublicGuild", publicly_listed: true) }
    let!(:private_guild) { create(:guild, name: "ZetaPrivateGuild", publicly_listed: false) }

    it "returns publicly listed guilds matching the query by guild name only (not owner username)" do
      listed_guild.owner.update!(username: "uniqueownersearchtoken")

      get guild_search_alliance_alliance_invites_path(alliance), params: { q: "uniqueownersearchtoken" }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["results"].map { |r| r["id"] }).not_to include(listed_guild.id)

      get guild_search_alliance_alliance_invites_path(alliance), params: { q: "ZetaPublic" }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["results"].map { |r| r["id"] }).to include(listed_guild.id)
    end

    it "returns publicly listed guilds matching the name for the alliance leader" do
      get guild_search_alliance_alliance_invites_path(alliance), params: { q: "Zeta" }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      body = response.parsed_body["results"]
      ids = body.map { |r| r["id"] }
      expect(ids).to include(listed_guild.id)
      expect(ids).not_to include(private_guild.id)
      row = body.find { |r| r["id"] == listed_guild.id }
      expect(row["inviteable"]).to be true
    end

    it "marks guilds already in an alliance as not inviteable" do
      other = create(:alliance, leader_guild: listed_guild, leader_user: listed_guild.owner)
      create(:alliance_guild, alliance: other, guild: listed_guild, status: :active)

      get guild_search_alliance_alliance_invites_path(alliance), params: { q: "ZetaPublic" }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      row = response.parsed_body["results"].find { |r| r["id"] == listed_guild.id }
      expect(row["inviteable"]).to be false
    end

    it "returns forbidden for an alliance member who is not the leader" do
      member_user = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: member_user, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      create(:guild_member, guild: guild, user: member_user, role: :member, status: :active)
      create(:alliance_member, alliance: alliance, user: member_user, guild: guild, role: :member, status: :active)

      sign_in member_user
      get guild_search_alliance_alliance_invites_path(alliance), params: { q: "Zeta" }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:forbidden)
    end

    it "returns forbidden for an alliance officer who is not the leader" do
      officer_user = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: officer_user, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      create(:guild_member, guild: guild, user: officer_user, role: :admin, status: :active)
      create(:alliance_member, alliance: alliance, user: officer_user, guild: guild, role: :officer, status: :active)

      sign_in officer_user
      get guild_search_alliance_alliance_invites_path(alliance), params: { q: "Zeta" }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:forbidden)
    end

    it "allows guild custom alliance managers to search invite targets" do
      create(:guild_member, guild: guild, user: custom_manager_user, role: :member, status: :active, discord_role_id: "role-manage-alliance")
      guild.update!(permission_role_1_id: "role-manage-alliance", role_1_can_manage_alliance: true)
      create(:alliance_member, alliance: alliance, user: custom_manager_user, guild: guild, role: :member, status: :active)

      sign_in custom_manager_user
      get guild_search_alliance_alliance_invites_path(alliance), params: { q: "Zeta" }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
    end

    it "paginates search results with page and per_page" do
      11.times do |i|
        create(:guild, name: "PagInviteGuild#{i}", publicly_listed: true)
      end

      get guild_search_alliance_alliance_invites_path(alliance),
          params: { q: "PagInviteGuild", page: 1, per_page: 10 },
          headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["results"].length).to eq(10)
      expect(json["pagination"]).to include(
        "page" => 1,
        "per_page" => 10,
        "total_count" => 11,
        "total_pages" => 2
      )

      get guild_search_alliance_alliance_invites_path(alliance),
          params: { q: "PagInviteGuild", page: 2, per_page: 10 },
          headers: { "Accept" => "application/json" }
      expect(response.parsed_body["results"].length).to eq(1)
      expect(response.parsed_body["pagination"]["page"]).to eq(2)
    end
  end

  describe "POST /alliances/:alliance_id/alliance_invites" do
    it "creates a pending invite for a guild not in an alliance" do
      expect {
        post alliance_alliance_invites_path(alliance), params: { guild_id: target_guild.id }
      }.to change(AllianceInvite, :count).by(1)
    end

    it "does not create an invite when the user lacks custom alliance permission" do
      officer_user = create(:user, :discord_auth, skip_free_plan_subscription: true)
      create(:subscription, user: officer_user, pricing_plan: active_paid_plan, status: :active, started_at: Time.current)
      create(:guild_member, guild: guild, user: officer_user, role: :admin, status: :active)
      create(:alliance_member, alliance: alliance, user: officer_user, guild: guild, role: :officer, status: :active)

      sign_in officer_user
      expect {
        post alliance_alliance_invites_path(alliance), params: { guild_id: target_guild.id }
      }.not_to change(AllianceInvite, :count)
      expect(response).to redirect_to(alliance_path(alliance))
    end

    it "creates an invite when user is a custom alliance manager" do
      create(:guild_member, guild: guild, user: custom_manager_user, role: :member, status: :active, discord_role_id: "role-manage-alliance")
      guild.update!(permission_role_1_id: "role-manage-alliance", role_1_can_manage_alliance: true)
      create(:alliance_member, alliance: alliance, user: custom_manager_user, guild: guild, role: :member, status: :active)
      sign_in custom_manager_user

      expect {
        post alliance_alliance_invites_path(alliance), params: { guild_id: target_guild.id }
      }.to change(AllianceInvite, :count).by(1)
    end

    it "does not invite a guild already in another active alliance" do
      other_alliance = create(:alliance, leader_guild: target_guild, leader_user: target_guild.owner)
      create(:alliance_guild, alliance: other_alliance, guild: target_guild, status: :active)

      expect {
        post alliance_alliance_invites_path(alliance), params: { guild_id: target_guild.id }
      }.not_to change(AllianceInvite, :count)
    end
  end
end
