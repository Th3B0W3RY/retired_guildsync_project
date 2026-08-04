# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Alliance events web RSVP", type: :request do
  let(:user) { create_alliance_paid_user!(:discord_auth) }
  let(:guild) { create(:guild, owner: user) }
  let(:alliance) { create(:alliance, leader_guild: guild, leader_user: user) }
  let(:event) { create(:alliance_event, alliance: alliance, created_by: user) }

  before do
    create(:alliance_guild, alliance: alliance, guild: guild, status: :active, joined_at: Time.current)
    create(:alliance_member, alliance: alliance, user: user, guild: guild, role: :gm, status: :active)
    sign_in user
  end

  describe "GET /alliances/:alliance_id/alliance_events" do
    it "renders the events index for an alliance member" do
      get alliance_alliance_events_path(alliance)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("alliances.events.index.title"))
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get alliance_alliance_events_path(alliance)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get alliance_alliance_events_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-events-index-support.example/help")
        get alliance_alliance_events_path(alliance)
        expect(response.body).to include("https://alliance-events-index-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-events-index-support.example/help")
        get alliance_alliance_events_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-events-index-support.example/help")
      end
    end
  end

  describe "GET /alliances/:alliance_id/alliance_events/new" do
    it "renders the new event form for the alliance owner" do
      get new_alliance_alliance_event_path(alliance)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("alliances.events.new.title"))
      expect(response.body).to include("pvp")
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get new_alliance_alliance_event_path(alliance)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get new_alliance_alliance_event_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-events-new-support.example/help")
        get new_alliance_alliance_event_path(alliance)
        expect(response.body).to include("https://alliance-events-new-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-events-new-support.example/help")
        get new_alliance_alliance_event_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-events-new-support.example/help")
      end
    end
  end

  describe "GET /alliances/:alliance_id/alliance_events/:id" do
    it "renders the event show page for an alliance member" do
      get alliance_alliance_event_path(alliance, event)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(event.title)
      expect(response.body).to include(I18n.t("alliances.events.show.your_rsvp"))
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        get alliance_alliance_event_path(alliance, event)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get alliance_alliance_event_path(alliance, event), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-events-show-support.example/help")
        get alliance_alliance_event_path(alliance, event)
        expect(response.body).to include("https://alliance-events-show-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-events-show-support.example/help")
        get alliance_alliance_event_path(alliance, event), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-events-show-support.example/help")
      end
    end
  end

  describe "management permissions" do
    let(:officer_user) { create_alliance_paid_user!(:discord_auth) }

    before do
      create(:alliance_member, alliance: alliance, user: officer_user, guild: guild, role: :officer, status: :active)
    end

    it "allows active guild owners to create events" do
      expect {
        post alliance_alliance_events_path(alliance), params: {
          alliance_event: { title: "Owner Event", scheduled_at: 1.day.from_now }
        }
      }.to change(AllianceEvent, :count).by(1)
    end

    it "blocks non-owner officers from creating events" do
      sign_in officer_user

      expect {
        post alliance_alliance_events_path(alliance), params: {
          alliance_event: { title: "Officer Event", scheduled_at: 1.day.from_now }
        }
      }.not_to change(AllianceEvent, :count)

      expect(response).to redirect_to(alliance_alliance_events_path(alliance))
    end
  end

  it "saves RSVP status from web endpoint" do
    post rsvp_alliance_alliance_event_path(alliance, event), params: { status: "maybe" }

    expect(response).to redirect_to(alliance_alliance_event_path(alliance, event))
    expect(flash[:notice]).to eq(I18n.t("alliances.events.rsvp_saved"))
    expect(AllianceEventParticipation.find_by(alliance_event: event, user: user)&.status).to eq("maybe")
  end

  it "syncs discord messages on update and delete lifecycle" do
    allow(AllianceDiscordBroadcastService).to receive(:broadcast_alliance_event_updated)
    allow(AllianceDiscordBroadcastService).to receive(:broadcast_alliance_event_deleted)

    patch alliance_alliance_event_path(alliance, event), params: { alliance_event: { title: "Updated Name" } }
    expect(response).to redirect_to(alliance_alliance_event_path(alliance, event))
    expect(AllianceDiscordBroadcastService).to have_received(:broadcast_alliance_event_updated).with(event)

    delete alliance_alliance_event_path(alliance, event)
    expect(response).to redirect_to(alliance_alliance_events_path(alliance))
    expect(AllianceDiscordBroadcastService).to have_received(:broadcast_alliance_event_deleted).with(event)
  end
end
