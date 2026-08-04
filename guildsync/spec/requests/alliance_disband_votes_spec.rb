# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AllianceDisbandVotes", type: :request do
  let(:owner)    { create_alliance_paid_user!(:discord_auth) }
  let(:guild)    { create(:guild, owner: owner) }
  let(:guild2)   { create(:guild, owner: create_alliance_paid_user!(:discord_auth)) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild,  alliance: a, guild: guild,  status: :active)
    create(:alliance_guild,  alliance: a, guild: guild2, status: :active)
    create(:alliance_member, alliance: a, user: owner,        guild: guild,  role: :gm, status: :active)
    create(:alliance_member, alliance: a, user: guild2.owner, guild: guild2, role: :gm, status: :active)
    a
  end

  before { sign_in owner }

  describe "GET /alliances/:alliance_id/alliance_disband_votes" do
    it "renders for a GM" do
      get alliance_alliance_disband_votes_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "rejects non-GMs" do
      member = create_alliance_paid_user!(:discord_auth)
      create(:alliance_member, alliance: alliance, user: member, guild: guild, role: :member, status: :active)
      sign_in member
      get alliance_alliance_disband_votes_path(alliance)
      expect(response).to redirect_to(alliance_path(alliance))
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get alliance_alliance_disband_votes_path(alliance)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get alliance_alliance_disband_votes_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-disband-votes-support.example/help")
        get alliance_alliance_disband_votes_path(alliance)
        expect(response.body).to include("https://alliance-disband-votes-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-disband-votes-support.example/help")
        get alliance_alliance_disband_votes_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-disband-votes-support.example/help")
      end
    end
  end

  describe "POST /alliances/:alliance_id/alliance_disband_votes" do
    it "records the vote without disbanding when minority" do
      expect {
        post alliance_alliance_disband_votes_path(alliance), params: { vote: "true" }
      }.to change(AllianceDisbandVote, :count).by(1)
      # Only 1 of 2 GMs voted — not a majority
      expect(alliance.reload).to be_active
    end

    it "disbands when majority vote to disband" do
      # Seed the other GM's vote first
      create(:alliance_disband_vote, alliance: alliance, user: guild2.owner, guild: guild2, vote: true)
      post alliance_alliance_disband_votes_path(alliance), params: { vote: "true" }
      expect(alliance.reload).to be_disbanded
      expect(response).to redirect_to(dashboard_path)
    end
  end
end
