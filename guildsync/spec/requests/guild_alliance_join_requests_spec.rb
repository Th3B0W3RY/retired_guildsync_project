# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guild alliance join requests", type: :request do
  let(:owner) { create(:user, :discord_auth) }
  let(:guild) { create(:guild, owner: owner) }
  let(:other) { create(:user, :discord_auth) }

  let(:paid_plan) do
    PricingPlan.find_or_create_by!(name: "Spec Paid Guild Alliance Join") do |p|
      p.price = 10
      p.price_display = "$10"
      p.period = "per month"
      p.max_guilds = 5
      p.max_members_per_guild = 50
      p.active = true
      p.display_order = 97
    end
  end

  let(:paid_owner) do
    u = create(:user, :discord_auth, skip_free_plan_subscription: true)
    create(:subscription, user: u, pricing_plan: paid_plan, status: :active)
    u
  end
  let(:paid_guild) { create(:guild, owner: paid_owner) }

  describe "GET /guilds/:guild_id/alliance_join_requests/new" do
    it "allows a paid-plan guild owner" do
      sign_in paid_owner
      get new_guild_alliance_join_request_path(paid_guild)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("alliances.outgoing_join_requests.new.title"))
    end

    it "redirects a stranger (no guild access)" do
      sign_in other
      get new_guild_alliance_join_request_path(guild)
      expect(response).to redirect_to(my_guilds_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "redirects when guild is already in an alliance" do
      a = create(:alliance, leader_guild: paid_guild, leader_user: paid_owner)
      create(:alliance_guild, alliance: a, guild: paid_guild, status: :active, joined_at: Time.current)
      sign_in paid_owner
      get new_guild_alliance_join_request_path(paid_guild)
      expect(response).to redirect_to(guild_path(paid_guild))
      expect(flash[:alert]).to eq(I18n.t("alliances.join_requests.errors.already_in_alliance"))
    end
  end

  describe "GET /alliances/guild_search" do
    it "returns 403 without guild_id" do
      sign_in paid_owner
      get alliances_guild_search_path, params: { q: "test" }
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 when guild_id is not owned" do
      sign_in paid_owner
      other_g = create(:guild)
      get alliances_guild_search_path, params: { q: "test", guild_id: other_g.id }
      expect(response).to have_http_status(:forbidden)
    end

    it "returns json when guild is owned" do
      sign_in paid_owner
      get alliances_guild_search_path, params: { q: "zz", guild_id: paid_guild.id }, headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "paginates JSON search results with page and per_page" do
      sign_in paid_owner
      11.times do |i|
        create(:guild, publicly_listed: true, name: "JoinReqPag #{i}")
      end

      get alliances_guild_search_path,
          params: { q: "JoinReqPag", guild_id: paid_guild.id, page: 1, per_page: 10 },
          headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["results"].size).to eq(10)
      expect(json["pagination"]).to include(
        "page" => 1,
        "per_page" => 10,
        "total_count" => 11,
        "total_pages" => 2
      )

      get alliances_guild_search_path,
          params: { q: "JoinReqPag", guild_id: paid_guild.id, page: 2, per_page: 10 },
          headers: { "Accept" => "application/json" }
      expect(response.parsed_body["results"].size).to eq(1)
      expect(response.parsed_body["pagination"]["page"]).to eq(2)
    end
  end
end
