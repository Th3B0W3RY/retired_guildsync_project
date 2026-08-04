# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Leaderboard", type: :request do
  let(:user) do
    # Skip Free plan subscription creation so we can create a test subscription
    u = create(:user, skip_free_plan_subscription: true)
    # Set auth_method to "discord" to bypass MFA checks in tests
    u.update!(auth_method: "discord")
    u
  end
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:subscription) { create(:subscription, user: user, pricing_plan: pricing_plan) }
  let(:guild) { create(:guild, owner: user) }
  # Owner membership is automatically created by guild factory
  let!(:discord_setting) { create(:guild_discord_setting, guild: guild, discord_guild_name: "Test Discord Server") }
  let(:default_support_url) { SiteSetting::DEFAULTS["release_notes_url"] }

  describe "GET /leaderboard" do
    before(:each) do
      sign_in user
    end

    describe "support_center_url in member chrome" do
      it "includes default support URL in HTML" do
        get leaderboard_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes default support URL on mobile variant" do
        get leaderboard_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response).to have_http_status(:success)
        expect(response.body).to include(default_support_url)
      end

      it "includes configured custom support URL when set" do
        SiteSetting.set("release_notes_url", "https://leaderboard-support.example/help")
        get leaderboard_path
        expect(response.body).to include("https://leaderboard-support.example/help")
      end

      it "includes configured custom support URL on mobile variant when set" do
        SiteSetting.set("release_notes_url", "https://leaderboard-support.example/help")
        get leaderboard_path, headers: mobile_user_agent_headers(MobileVariantRequestHelpers::IPHONE_SAFARI_UA)
        expect(response.body).to include("https://leaderboard-support.example/help")
      end
    end

    context "when user has no events" do
      it "returns empty leaderboard" do
        get leaderboard_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("No participation data available yet")
      end
    end

    context "when events exist but no participations" do
      let!(:event) { create(:event, guild: guild, status: :in_progress) }

      it "returns empty leaderboard" do
        get leaderboard_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("No participation data available yet")
      end
    end

    context "when events have participations but not on_time" do
      let!(:event) { create(:event, guild: guild, status: :in_progress) }
      let!(:participation) { create(:discord_event_participation, event: event, on_time: false) }

      it "returns empty leaderboard" do
        get leaderboard_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include("No participation data available yet")
      end
    end

    context "when events have on_time participations" do
      let!(:event1) { create(:event, guild: guild, status: :in_progress, scheduled_at: 1.day.ago) }
      let!(:event2) { create(:event, guild: guild, status: :completed, scheduled_at: 2.days.ago) }
      let!(:event3) { create(:event, guild: guild, status: :scheduled, scheduled_at: 1.day.from_now) } # Should not be included

      let!(:participation1) do
        create(:discord_event_participation,
               event: event1,
               discord_username: "User1#1234",
               discord_user_id: "user1_id",
               on_time: true)
      end

      let!(:participation2) do
        create(:discord_event_participation,
               event: event2,
               discord_username: "User1#1234",
               discord_user_id: "user1_id",
               on_time: true)
      end

      let!(:participation3) do
        create(:discord_event_participation,
               event: event2,
               discord_username: "User2#5678",
               discord_user_id: "user2_id",
               on_time: true)
      end

      let!(:participation4) do
        create(:discord_event_participation,
               event: event3,
               discord_username: "User3#9999",
               discord_user_id: "user3_id",
               on_time: true) # Scheduled events should not be included
      end

      it "returns leaderboard with correct data" do
        get leaderboard_path
        expect(response).to have_http_status(:success)
        # clean_discord_username strips the discriminator (#1234), so we expect "User1" not "User1#1234"
        expect(response.body).to include("User1")
        expect(response.body).to include("User2")
        expect(response.body).to include("Test Discord Server")
        expect(response.body).to include("20") # User1: 2 on-time events × 10
        expect(response.body).to include("10") # User2: 1 on-time event × 10
        expect(response.body).not_to include("User3") # Scheduled event not included
      end

      it "sorts leaderboard by weighted score descending" do
        get leaderboard_path
        expect(response).to have_http_status(:success)
        body = response.body
        # clean_discord_username strips the discriminator, so we expect "User1" not "User1#1234"
        user1_index = body.index("User1")
        user2_index = body.index("User2")
        expect(user1_index).to be < user2_index # User1 should appear first
      end
    end

    context "when guild has no discord setting" do
      let!(:guild_without_discord) { create(:guild, owner: user) }
      # Owner membership is automatically created by guild factory
      let!(:event) { create(:event, guild: guild_without_discord, status: :in_progress) }
      let!(:participation) do
        create(:discord_event_participation,
               event: event,
               discord_username: "User1#1234",
               on_time: true)
      end

      it "uses guild name as fallback for server name" do
        get leaderboard_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include(guild_without_discord.name)
      end
    end

    context "when user has multiple guilds" do
      let(:guild2) { create(:guild, owner: user) }
      # Owner membership is automatically created by guild factory
      let!(:discord_setting2) { create(:guild_discord_setting, guild: guild2, discord_guild_name: "Second Discord Server") }

      let!(:event1) { create(:event, guild: guild, status: :in_progress) }
      let!(:event2) { create(:event, guild: guild2, status: :completed) }

      let!(:participation1) do
        create(:discord_event_participation,
               event: event1,
               discord_username: "User1#1234",
               discord_user_id: "user1_id",
               on_time: true)
      end

      let!(:participation2) do
        create(:discord_event_participation,
               event: event2,
               discord_username: "User1#1234",
               discord_user_id: "user1_id",
               on_time: true)
      end

      it "includes participations from all user's guilds" do
        get leaderboard_path
        expect(response).to have_http_status(:success)
        # clean_discord_username strips the discriminator, so we expect "User1" not "User1#1234"
        expect(response.body).to include("User1")
        expect(response.body).to include("Test Discord Server")
        expect(response.body).to include("Second Discord Server")
      end
    end

    context "when user is not member of guild" do
      let(:other_user) do
        # Skip Free plan subscription creation so we can create a test subscription
        u = create(:user, skip_free_plan_subscription: true)
        u.update!(auth_method: "discord")
        u
      end
      let!(:other_plan) { create(:pricing_plan, max_guilds: 10) }
      let!(:other_subscription) { create(:subscription, user: other_user, pricing_plan: other_plan) }
      let(:other_guild) { create(:guild, owner: other_user) }
      let!(:other_event) { create(:event, guild: other_guild, status: :in_progress) }
      let!(:other_participation) do
        create(:discord_event_participation,
               event: other_event,
               discord_username: "OtherUser#1234",
               on_time: true)
      end

      it "does not include events from other guilds" do
        get leaderboard_path
        expect(response).to have_http_status(:success)
        expect(response.body).not_to include("OtherUser#1234")
      end
    end
  end
end

