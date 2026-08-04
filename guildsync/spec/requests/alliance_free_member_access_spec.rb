# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Alliance access for trial/free alliance members", type: :request do
  let(:paid_owner) { create_alliance_paid_user!(:discord_auth) }
  let(:guild) { create(:guild, owner: paid_owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: paid_owner)
    create(:alliance_guild, alliance: a, guild: guild, status: :active, joined_at: Time.current)
    create(:alliance_member, alliance: a, user: paid_owner, guild: guild, role: :gm, status: :active)
    a
  end

  let(:free_member) { create(:user, :discord_auth) }

  before do
    alliance
    # Joining the guild triggers AllianceMemberSyncService (guild is in an active alliance).
    create(:guild_member, guild: guild, user: free_member, role: :member, status: :active)
    sign_in free_member
  end

  describe "read paths" do
    it "allows GET alliance show" do
      get alliance_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "allows GET alliance events index" do
      get alliance_alliance_events_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "allows GET alliance members index" do
      get alliance_alliance_members_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "allows GET alliance polls index" do
      get alliance_alliance_polls_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "allows GET alliance loot rolls index" do
      get alliance_alliance_loot_rolls_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "allows GET alliance messages" do
      get alliance_alliance_messages_path(alliance)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "participation" do
    let(:event) { create(:alliance_event, alliance: alliance, created_by: paid_owner) }
    let(:poll) { create(:alliance_poll, alliance: alliance, creator: paid_owner, deadline: 1.week.from_now) }
    let(:loot_roll) { create(:alliance_loot_roll, alliance: alliance, creator: paid_owner) }

    it "allows RSVP" do
      post rsvp_alliance_alliance_event_path(alliance, event), params: { status: "maybe" }
      expect(response).to redirect_to(alliance_alliance_event_path(alliance, event))
      expect(AllianceEventParticipation.find_by(alliance_event: event, user: free_member)&.status).to eq("maybe")
    end

    it "allows poll vote" do
      post vote_alliance_alliance_poll_path(alliance, poll), params: { choice: 0 }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
    end

    it "allows loot roll enter" do
      expect {
        post enter_alliance_alliance_loot_roll_path(alliance, loot_roll)
      }.to change(AllianceLootRollEntry, :count).by(1)
    end

    it "allows alliance chat post" do
      expect {
        post alliance_alliance_messages_path(alliance),
             params: { alliance_message: { content: "Hi from free member" }, message_type: "all_members" },
             as: :json
      }.to change(AllianceMessage, :count).by(1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "management remains blocked without custom permissions" do
    it "blocks creating a poll" do
      expect {
        post alliance_alliance_polls_path(alliance), params: {
          alliance_poll: { title: "Nope", deadline: 1.week.from_now, anonymous: false }
        }
      }.not_to change(AlliancePoll, :count)
      expect(response).to redirect_to(alliance_alliance_polls_path(alliance))
    end

    it "blocks creating a loot roll" do
      expect {
        post alliance_alliance_loot_rolls_path(alliance), params: {
          alliance_loot_roll: { title: "Nope", min_roll: 1, max_roll: 100, anonymous: false }
        }
      }.not_to change(AllianceLootRoll, :count)
      expect(response).to redirect_to(alliance_alliance_loot_rolls_path(alliance))
    end

    it "blocks creating an event" do
      expect {
        post alliance_alliance_events_path(alliance), params: {
          alliance_event: { title: "Nope", scheduled_at: 1.day.from_now }
        }
      }.not_to change(AllianceEvent, :count)
      expect(response).to redirect_to(alliance_alliance_events_path(alliance))
    end
  end

  describe "alliance disband votes (GM-only; paid-plan gate + active-member exemption)" do
    it "denies non-owning free members who are not GMs of a guild in the alliance" do
      get alliance_alliance_disband_votes_path(alliance)
      expect(response).to redirect_to(alliance_path(alliance))
      expect(flash[:alert]).to eq(I18n.t("alliances.disband_votes.errors.not_gm"))
    end

    context "when the alliance leader downgrades to Free but stays an active alliance member" do
      let(:free_plan) do
        plan = PricingPlan.find_or_create_by!(name: "Free") do |p|
          p.price = 0
          p.price_display = "$0"
          p.period = "forever"
          p.max_guilds = 1
          p.max_members_per_guild = 10
          p.active = true
          p.display_order = 0
        end
        plan.update!(price: 0) if plan.price.nil? || !plan.price.zero?
        plan
      end
      let(:peer_guild) { create(:guild, owner: create_alliance_paid_user!(:discord_auth)) }

      before do
        create(:alliance_guild, alliance: alliance, guild: peer_guild, status: :active, joined_at: Time.current)
        create(:alliance_member, alliance: alliance, user: peer_guild.owner, guild: peer_guild, role: :gm, status: :active)
        paid_owner.current_subscription.update!(pricing_plan: free_plan)
        paid_owner.reload
        sign_in paid_owner
      end

      it "allows GET disband votes index as guild owner (GM)" do
        get alliance_alliance_disband_votes_path(alliance)
        expect(response).to have_http_status(:ok)
      end

      it "allows POST disband vote without majority disband (two active guilds)" do
        expect {
          post alliance_alliance_disband_votes_path(alliance), params: { vote: "true" }
        }.to change(AllianceDisbandVote, :count).by(1)
        expect(alliance.reload).to be_active
        expect(response).to redirect_to(alliance_alliance_disband_votes_path(alliance))
      end
    end
  end

  describe "alliance activity feed (owner-only + plan exemption)" do
    it "denies non-owning free members" do
      get alliance_activity_feed_path(alliance_id: alliance.id)
      expect(response).to redirect_to(alliance_path(alliance))
      expect(flash[:alert]).to eq(I18n.t("alliance_activity_feed.access_denied"))
    end

    context "when the alliance leader downgrades to Free but stays an active alliance member" do
      let(:free_plan) do
        plan = PricingPlan.find_or_create_by!(name: "Free") do |p|
          p.price = 0
          p.price_display = "$0"
          p.period = "forever"
          p.max_guilds = 1
          p.max_members_per_guild = 10
          p.active = true
          p.display_order = 0
        end
        plan.update!(price: 0) if plan.price.nil? || !plan.price.zero?
        plan
      end

      before do
        paid_owner.current_subscription.update!(pricing_plan: free_plan)
        paid_owner.reload
        sign_in paid_owner
      end

      it "allows GET alliance activity feed" do
        get alliance_activity_feed_path(alliance_id: alliance.id)
        expect(response).to have_http_status(:ok)
      end

      it "allows GET alliance activity feed CSV export" do
        AllianceActivityLog.create!(
          alliance: alliance,
          guild: guild,
          user: paid_owner,
          action_type: "free_leader_export_csv",
          description: "Leader on Free tier",
          metadata: {}
        )

        get alliance_activity_feed_export_path(alliance_id: alliance.id, action_type: "free_leader_export_csv")

        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("text/csv")
        expect(response.body).to include("free_leader_export_csv")
        expect(response.body).to include("Leader on Free tier")
      end

      it "allows GET alliance activity feed export.json" do
        AllianceActivityLog.create!(
          alliance: alliance,
          guild: guild,
          user: paid_owner,
          action_type: "free_leader_export_json",
          description: "JSON row",
          metadata: { "k" => "v" }
        )

        get alliance_activity_feed_export_json_path(alliance_id: alliance.id)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["alliance_id"]).to eq(alliance.id)
        expect(json["rows"].size).to eq(1)
        expect(json["rows"].first["action"]).to eq("free_leader_export_json")
      end
    end
  end

  describe "guild_search on alliances hub" do
    let(:solo_guild) { create(:guild, owner: free_member) }

    before { solo_guild }

    it "returns forbidden for trial/free users even when alliance member" do
      get alliances_guild_search_path, params: { guild_id: solo_guild.id, q: "test" }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
