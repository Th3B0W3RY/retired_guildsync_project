# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AlliancePolls", type: :request do
  let(:owner)    { create_alliance_paid_user!(:discord_auth) }
  let(:guild)    { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild,  alliance: a, guild: guild, status: :active)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end
  let(:regular_user) { create_alliance_paid_user!(:discord_auth) }
  let(:officer_user) { create_alliance_paid_user!(:discord_auth) }
  let(:custom_manager_user) { create_alliance_paid_user!(:discord_auth) }

  before do
    create(:alliance_member, alliance: alliance, user: regular_user, guild: guild, role: :member, status: :active)
    create(:alliance_member, alliance: alliance, user: officer_user, guild: guild, role: :officer, status: :active)
    create(:alliance_member, alliance: alliance, user: custom_manager_user, guild: guild, role: :member, status: :active)
    create(:guild_member, guild: guild, user: regular_user, role: :member, status: :active)
    create(:guild_member, guild: guild, user: officer_user, role: :admin, status: :active)
    create(:guild_member, guild: guild, user: custom_manager_user, role: :member, status: :active, discord_role_id: "role-manage-alliance")
    guild.update!(permission_role_1_id: "role-manage-alliance", role_1_can_manage_alliance: true)
    sign_in owner
  end

  describe "GET /alliances/:alliance_id/alliance_polls" do
    it "renders the polls index for members" do
      get alliance_alliance_polls_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "redirects to dashboard with access_denied for an unknown alliance id" do
      get alliance_alliance_polls_path(0)
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "redirects to dashboard with access_denied when the user is not an alliance member" do
      outsider = create_alliance_paid_user!(:discord_auth)
      sign_in outsider
      get alliance_alliance_polls_path(alliance)
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to eq(I18n.t("controllers.guilds.access_denied"))
    end

    it "renders translated index title" do
      get alliance_alliance_polls_path(alliance)
      expect(response.body).to include(I18n.t("alliance_polls.index.title"))
    end

    it "lists voter names on non-anonymous polls" do
      voter = regular_user
      poll = create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now, anonymous: false)
      poll.alliance_poll_votes.create!(user: voter, choice: :yes)
      get alliance_alliance_polls_path(alliance)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(voter.display_name)
    end

    it "does not list voter names for anonymous polls" do
      voter = regular_user
      poll = create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now, anonymous: true)
      poll.alliance_poll_votes.create!(user: voter, choice: :yes)
      get alliance_alliance_polls_path(alliance)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(voter.display_name)
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get alliance_alliance_polls_path(alliance)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get alliance_alliance_polls_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-polls-index-support.example/help")
        get alliance_alliance_polls_path(alliance)
        expect(response.body).to include("https://alliance-polls-index-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-polls-index-support.example/help")
        get alliance_alliance_polls_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-polls-index-support.example/help")
      end
    end
  end

  describe "GET /alliances/:alliance_id/alliance_polls/:id" do
    it "shows voter names on the poll page when not anonymous" do
      poll = create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now, anonymous: false)
      poll.alliance_poll_votes.create!(user: regular_user, choice: :yes)
      get alliance_alliance_poll_path(alliance, poll)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(regular_user.display_name)
    end

    it "does not show voter names on the poll page when anonymous" do
      poll = create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now, anonymous: true)
      poll.alliance_poll_votes.create!(user: regular_user, choice: :yes)
      get alliance_alliance_poll_path(alliance, poll)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(regular_user.display_name)
    end

    it "wires alliance-poll-vote Stimulus for open polls without full reload" do
      poll = create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now)
      get alliance_alliance_poll_path(alliance, poll)
      expect(response.body).not_to include("window.location.reload")
      expect(response.body).to include('data-controller="alliance-poll-vote"')
      expect(response.body).to include("alliance-poll-vote#vote")
      expect(response.body).to include("data-alliance-poll-vote-poll-id-value")
    end

    it "does not attach alliance-poll-vote when poll is closed" do
      poll = create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.day.ago)
      get alliance_alliance_poll_path(alliance, poll)
      expect(response.body).not_to include('data-controller="alliance-poll-vote"')
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }
      let(:open_poll) { create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now) }

      it "includes default support URL in HTML" do
        get alliance_alliance_poll_path(alliance, open_poll)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get alliance_alliance_poll_path(alliance, open_poll), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-polls-show-support.example/help")
        get alliance_alliance_poll_path(alliance, open_poll)
        expect(response.body).to include("https://alliance-polls-show-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-polls-show-support.example/help")
        get alliance_alliance_poll_path(alliance, open_poll), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-polls-show-support.example/help")
      end
    end
  end

  describe "POST /alliances/:alliance_id/alliance_polls" do
    it "creates a poll as owner" do
      expect {
        post alliance_alliance_polls_path(alliance), params: {
          alliance_poll: { title: "Should we do a raid?", deadline: 1.week.from_now, anonymous: false }
        }
      }.to change(AlliancePoll, :count).by(1)
    end

    it "allows custom alliance managers to create polls" do
      sign_in custom_manager_user
      expect {
        post alliance_alliance_polls_path(alliance), params: {
          alliance_poll: { title: "Manager poll", deadline: 1.week.from_now, anonymous: false }
        }
      }.to change(AlliancePoll, :count).by(1)
    end

    it "blocks officers without custom alliance permissions from creating polls" do
      sign_in officer_user
      expect {
        post alliance_alliance_polls_path(alliance), params: {
          alliance_poll: { title: "Officer poll", deadline: 1.week.from_now, anonymous: false }
        }
      }.not_to change(AlliancePoll, :count)
    end

    it "blocks regular members from creating polls" do
      sign_in regular_user
      expect {
        post alliance_alliance_polls_path(alliance), params: {
          alliance_poll: { title: "Unauthorized poll", deadline: 1.week.from_now, anonymous: false }
        }
      }.not_to change(AlliancePoll, :count)
    end
  end

  describe "POST /alliances/:alliance_id/alliance_polls/:id/vote" do
    let(:poll) { create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now) }

    it "allows members to vote" do
      sign_in regular_user
      post vote_alliance_alliance_poll_path(alliance, poll), params: { choice: 0 },
           as: :json
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
    end

    it "broadcasts vote_update via AlliancePollsChannel" do
      sign_in regular_user
      expect(AlliancePollsChannel).to receive(:broadcast_to).with(
        poll,
        hash_including(type: "vote_update", vote_counts: hash_including(yes: 1))
      ).and_call_original
      post vote_alliance_alliance_poll_path(alliance, poll), params: { choice: 0 }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "prevents voting on closed polls" do
      poll.update!(deadline: 1.day.ago)
      post vote_alliance_alliance_poll_path(alliance, poll), params: { choice: 0 }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns voters_by_choice for non-anonymous polls" do
      poll = create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now, anonymous: false)
      sign_in regular_user
      post vote_alliance_alliance_poll_path(alliance, poll), params: { choice: 0 }, as: :json
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["vote_counts"]["yes"]).to eq(1)
      expect(json["voters_by_choice"]["yes"]).to include(regular_user.name_for_discord_embed)
    end

    it "omits voters_by_choice for anonymous polls" do
      poll = create(:alliance_poll, alliance: alliance, creator: owner, deadline: 1.week.from_now, anonymous: true)
      sign_in regular_user
      post vote_alliance_alliance_poll_path(alliance, poll), params: { choice: 0 }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key("voters_by_choice")
    end
  end
end
