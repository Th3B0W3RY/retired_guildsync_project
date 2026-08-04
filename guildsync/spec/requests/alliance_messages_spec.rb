# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AllianceMessages", type: :request do
  let(:owner)    { create_alliance_paid_user!(:discord_auth) }
  let(:guild)    { create(:guild, owner: owner) }
  let(:alliance) do
    a = create(:alliance, leader_guild: guild, leader_user: owner)
    create(:alliance_guild,  alliance: a, guild: guild, status: :active)
    create(:alliance_member, alliance: a, user: owner, guild: guild, role: :gm, status: :active)
    a
  end
  let(:member_user) { create_alliance_paid_user!(:discord_auth) }
  let(:officer_user) { create_alliance_paid_user!(:discord_auth) }

  before do
    create(:alliance_member, alliance: alliance, user: member_user, guild: guild, role: :member, status: :active)
    create(:alliance_member, alliance: alliance, user: officer_user, guild: guild, role: :officer, status: :active)
  end

  describe "GET /alliances/:alliance_id/alliance_messages (all_members)" do
    it "renders for alliance members" do
      sign_in member_user
      get alliance_alliance_messages_path(alliance)
      expect(response).to have_http_status(:ok)
    end

    it "avoids full page reload after post (client appends from JSON)" do
      sign_in member_user
      get alliance_alliance_messages_path(alliance)
      expect(response.body).not_to include("window.location.reload")
      expect(response.body).to include("appendMessageRow")
      expect(response.body).to include("pollNewMessages")
      expect(response.body).to include('data-controller="alliance-chat"')
      expect(response.body).to include("alliance-chat:message")
      expect(response.body).to include("alliance-chat:connected")
      expect(response.body).to include("alliance-chat:disconnected")
      expect(response.body).to include("POLL_MS_WITH_CABLE")
      expect(response.body).to include("30000")
    end

    it "renders machine-readable timestamps and locale-specific display time" do
      msg = create(:alliance_message, alliance: alliance, sender: member_user, message_type: :all_members, content: "Timestamp test")
      sign_in member_user

      get alliance_alliance_messages_path(alliance, locale: :de)

      expect(response.body).to include("class=\"js-local-time\"")
      expect(response.body).to include("datetime=\"")
      expect(response.body).to include("data-fallback=\"")
      expected_display = I18n.l(msg.created_at, format: I18n.t("alliances.messages.index.message_time_format", locale: :de))
      expect(response.body).to include(expected_display)
      expect(response.body).to match(/const\s+pageLocale\s*=\s*"de"/)
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        sign_in member_user
        get alliance_alliance_messages_path(alliance)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        sign_in member_user
        get alliance_alliance_messages_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-messages-support.example/help")
        sign_in member_user
        get alliance_alliance_messages_path(alliance)
        expect(response.body).to include("https://alliance-messages-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-messages-support.example/help")
        sign_in member_user
        get alliance_alliance_messages_path(alliance), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-messages-support.example/help")
      end
    end
  end

  describe "GET /alliances/:alliance_id/alliance_messages?type=gm" do
    it "allows GMs to view gm chat" do
      sign_in owner
      get alliance_alliance_messages_path(alliance, type: "gm")
      expect(response).to have_http_status(:ok)
    end

    it "blocks regular members from gm chat" do
      sign_in member_user
      get alliance_alliance_messages_path(alliance, type: "gm")
      expect(response).to redirect_to(alliance_alliance_messages_path(alliance))
    end

    it "blocks officers from gm chat" do
      sign_in officer_user
      get alliance_alliance_messages_path(alliance, type: "gm")
      expect(response).to redirect_to(alliance_alliance_messages_path(alliance))
    end

    describe "support_center_url in member chrome" do
      let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

      it "includes default support URL in HTML" do
        sign_in owner
        get alliance_alliance_messages_path(alliance, type: "gm")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        sign_in owner
        get alliance_alliance_messages_path(alliance, type: "gm"), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://alliance-messages-gm-support.example/help")
        sign_in owner
        get alliance_alliance_messages_path(alliance, type: "gm")
        expect(response.body).to include("https://alliance-messages-gm-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://alliance-messages-gm-support.example/help")
        sign_in owner
        get alliance_alliance_messages_path(alliance, type: "gm"), headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://alliance-messages-gm-support.example/help")
      end
    end
  end

  describe "GET /alliances/:alliance_id/alliance_messages.json (poll)" do
    let!(:older_msg) do
      create(:alliance_message, alliance: alliance, sender: owner, message_type: :all_members, content: "Older")
    end
    let!(:newer_msg) do
      create(:alliance_message, alliance: alliance, sender: owner, message_type: :all_members, content: "Newer")
    end

    it "returns messages with id greater than since_id" do
      sign_in member_user
      get alliance_alliance_messages_path(alliance, format: :json, since_id: older_msg.id)
      expect(response).to have_http_status(:ok)
      list = response.parsed_body["messages"]
      expect(list.length).to eq(1)
      expect(list[0]["id"]).to eq(newer_msg.id)
      expect(list[0]).to include("content", "sender", "sender_id", "created_at", "display_time")
    end

    it "returns empty messages when since_id is latest id" do
      sign_in member_user
      get alliance_alliance_messages_path(alliance, format: :json, since_id: newer_msg.id)
      expect(response.parsed_body["messages"]).to eq([])
    end

    it "returns empty messages when since_id is zero" do
      sign_in member_user
      get alliance_alliance_messages_path(alliance, format: :json, since_id: 0)
      expect(response.parsed_body["messages"]).to eq([])
    end

    it "returns forbidden for gm poll when user is not a guild owner" do
      sign_in member_user
      get alliance_alliance_messages_path(alliance, format: :json, type: "gm", since_id: 0)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /alliances/:alliance_id/alliance_messages" do
    before { sign_in member_user }

    it "creates an all_members message" do
      expect {
        post alliance_alliance_messages_path(alliance),
             params: { alliance_message: { content: "Hello!" }, message_type: "all_members" },
             as: :json
      }.to change(AllianceMessage, :count).by(1)
      expect(response).to have_http_status(:ok)
    end

    it "returns JSON for client-side append with sender_id, display_time, and UTC created_at" do
      post alliance_alliance_messages_path(alliance),
           params: { alliance_message: { content: "Append me" }, message_type: "all_members" },
           as: :json
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["content"]).to eq("Append me")
      expect(body["sender_id"]).to eq(member_user.id)
      expect(body["display_time"]).to be_present
      expect(body["created_at"]).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it "broadcasts new messages to the alliance chat Action Cable stream" do
      stream = AllianceMessagesChannel.stream_name(alliance.id, "all_members")
      expect(ActionCable.server).to receive(:broadcast).with(
        stream,
        satisfy { |payload|
          payload[:type] == "message" &&
            payload[:message][:content] == "Cable hi" &&
            payload[:message][:sender_id] == member_user.id
        }
      )
      post alliance_alliance_messages_path(alliance),
           params: { alliance_message: { content: "Cable hi" }, message_type: "all_members" },
           as: :json
      expect(response).to have_http_status(:ok)
    end

    it "blocks regular members from creating gm_only messages" do
      expect {
        post alliance_alliance_messages_path(alliance),
             params: { alliance_message: { content: "GM msg" }, message_type: "gm_only" },
             as: :json
      }.not_to change(AllianceMessage, :count)
    end

    it "allows GMs to create gm_only messages" do
      sign_in owner
      expect {
        post alliance_alliance_messages_path(alliance),
             params: { alliance_message: { content: "GM only" }, message_type: "gm_only" },
             as: :json
      }.to change(AllianceMessage, :count).by(1)
    end

    it "broadcasts gm_only messages to the gm stream" do
      sign_in owner
      stream = AllianceMessagesChannel.stream_name(alliance.id, "gm_only")
      expect(ActionCable.server).to receive(:broadcast).with(stream, anything)
      post alliance_alliance_messages_path(alliance),
           params: { alliance_message: { content: "GM cable" }, message_type: "gm_only" },
           as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
