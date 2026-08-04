# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Event, type: :model do
  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }
  let(:user) { create(:user) }
  let(:guild) { create(:guild, owner: user) }

  describe "associations" do
    it "belongs to a guild" do
      event = create(:event, guild: guild, created_by: user)
      expect(event.guild).to eq(guild)
    end

    it "belongs to created_by user" do
      event = create(:event, guild: guild, created_by: user)
      expect(event.created_by).to eq(user)
    end

    it "has many event_participations" do
      event = create(:event, guild: guild, created_by: user)
      participation = create(:event_participation, event: event, user: create(:user))
      expect(event.event_participations).to include(participation)
    end

    it "has many participants through event_participations" do
      event = create(:event, guild: guild, created_by: user)
      participant = create(:user)
      create(:event_participation, event: event, user: participant)
      expect(event.participants).to include(participant)
    end

    it "has many discord_event_participations" do
      event = create(:event, guild: guild, created_by: user)
      participation = create(:discord_event_participation, event: event)
      expect(event.discord_event_participations).to include(participation)
    end
  end

  describe "validations" do
    it "requires a title" do
      event = build(:event, guild: guild, created_by: user, title: nil)
      expect(event).not_to be_valid
      expect(event.errors[:title]).to be_present
    end

    it "requires title to be at least 3 characters" do
      event = build(:event, guild: guild, created_by: user, title: "ab")
      expect(event).not_to be_valid
      expect(event.errors[:title]).to be_present
    end

    it "requires title to be at most 200 characters" do
      event = build(:event, guild: guild, created_by: user, title: "a" * 201)
      expect(event).not_to be_valid
      expect(event.errors[:title]).to be_present
    end

    it "accepts title between 3 and 200 characters" do
      event = build(:event, guild: guild, created_by: user, title: "Valid Event Title")
      expect(event).to be_valid
    end

    it "requires scheduled_at" do
      event = build(:event, guild: guild, created_by: user, scheduled_at: nil)
      expect(event).not_to be_valid
      expect(event.errors[:scheduled_at]).to be_present
    end

    it "requires duration to be greater than 0 if present" do
      event = build(:event, guild: guild, created_by: user, duration: 0)
      expect(event).not_to be_valid
      expect(event.errors[:duration]).to be_present
    end

    it "allows duration to be nil" do
      event = build(:event, guild: guild, created_by: user, duration: nil)
      expect(event).to be_valid
    end

    it "accepts positive duration values" do
      event = build(:event, guild: guild, created_by: user, duration: 60)
      expect(event).to be_valid
    end
  end

  describe "enums" do
    it "has status enum with correct values" do
      event = create(:event, guild: guild, created_by: user)
      expect(event.status).to eq("scheduled")

      event.status = :in_progress
      expect(event.status).to eq("in_progress")

      event.status = :completed
      expect(event.status).to eq("completed")

      event.status = :cancelled
      expect(event.status).to eq("cancelled")
    end
  end

  describe "scopes" do
    let!(:past_event) { create(:event, guild: guild, created_by: user, scheduled_at: 1.day.ago) }
    let!(:upcoming_event) { create(:event, guild: guild, created_by: user, scheduled_at: 1.day.from_now) }

    describe ".upcoming" do
      it "returns events scheduled in the future" do
        upcoming = Event.upcoming
        expect(upcoming).to include(upcoming_event)
        expect(upcoming).not_to include(past_event)
      end

      it "orders events by scheduled_at ascending" do
        event1 = create(:event, guild: guild, created_by: user, scheduled_at: 3.days.from_now)
        event2 = create(:event, guild: guild, created_by: user, scheduled_at: 2.days.from_now)

        upcoming = Event.upcoming
        expect(upcoming.first).to eq(upcoming_event)
        expect(upcoming.second).to eq(event2)
        expect(upcoming.third).to eq(event1)
      end
    end

    describe ".past" do
      it "returns events scheduled in the past" do
        past = Event.past
        expect(past).to include(past_event)
        expect(past).not_to include(upcoming_event)
      end

      it "orders events by scheduled_at descending" do
        event1 = create(:event, guild: guild, created_by: user, scheduled_at: 3.days.ago)
        event2 = create(:event, guild: guild, created_by: user, scheduled_at: 2.days.ago)

        past = Event.past
        expect(past.first).to eq(past_event)
        expect(past.second).to eq(event2)
        expect(past.third).to eq(event1)
      end
    end
  end

  describe "event creation flow" do
    it "creates a valid event with all required attributes" do
      event = Event.create!(
        guild: guild,
        created_by: user,
        title: "Test Event",
        description: "A test event description",
        scheduled_at: 1.hour.from_now,
        duration: 60,
        status: :scheduled
      )

      expect(event).to be_persisted
      expect(event.title).to eq("Test Event")
      expect(event.guild).to eq(guild)
      expect(event.created_by).to eq(user)
      expect(event.status).to eq("scheduled")
    end

    it "defaults status to scheduled when not specified" do
      event = create(:event, guild: guild, created_by: user)
      expect(event.status).to eq("scheduled")
    end
  end

  describe "status transitions" do
    let(:event) { create(:event, guild: guild, created_by: user, status: :scheduled) }

    it "can transition from scheduled to in_progress" do
      event.update!(status: :in_progress)
      expect(event.status).to eq("in_progress")
    end

    it "can transition from in_progress to completed" do
      event.update!(status: :in_progress)
      event.update!(status: :completed)
      expect(event.status).to eq("completed")
    end

    it "can transition from scheduled to cancelled" do
      event.update!(status: :cancelled)
      expect(event.status).to eq("cancelled")
    end
  end

  describe "callbacks" do
    describe "#mark_participants_on_time" do
      let(:user) { create(:user) }
      let!(:plan) do
        PricingPlan.find_or_create_by!(name: "Test Plan") do |p|
          p.price_display = "$0"
          p.period = "forever"
          p.max_guilds = 10
          p.max_members_per_guild = 100
          p.active = true
        end
      end
      let!(:subscription) { create(:subscription, user: user, pricing_plan: plan) }
      let(:guild) { create(:guild, owner: user) }
      let(:event) { create(:event, guild: guild, created_by: user, status: :scheduled) }

      context "when event status changes from scheduled to in_progress" do
        let!(:participation1) do
          create(:discord_event_participation,
                 event: event,
                 discord_username: "User1#1234",
                 discord_user_id: "user1_id",
                 on_time: false)
        end

        let!(:participation2) do
          create(:discord_event_participation,
                 event: event,
                 discord_username: "User2#5678",
                 discord_user_id: "user2_id",
                 on_time: false)
        end

        it "marks all existing participations as on_time" do
          expect(event.discord_event_participations.where(on_time: true).count).to eq(0)

          event.update!(status: :in_progress)

          expect(event.discord_event_participations.where(on_time: true).count).to eq(2)
          expect(participation1.reload.on_time).to be true
          expect(participation2.reload.on_time).to be true
        end
      end

      context "when event status changes to something other than in_progress" do
        let!(:participation) do
          create(:discord_event_participation,
                 event: event,
                 discord_username: "User1#1234",
                 discord_user_id: "user1_id",
                 on_time: false)
        end

        it "does not mark participations as on_time" do
          event.update!(status: :completed)

          expect(participation.reload.on_time).to be false
        end
      end

      context "when event status changes from in_progress to completed" do
        let(:event) { create(:event, guild: guild, created_by: user, status: :in_progress) }
        let!(:participation) do
          create(:discord_event_participation,
                 event: event,
                 discord_username: "User1#1234",
                 discord_user_id: "user1_id",
                 on_time: true)
        end

        it "does not change existing on_time status" do
          event.update!(status: :completed)

          expect(participation.reload.on_time).to be true
        end
      end

      context "when new participations are added after event starts" do
        let(:event) { create(:event, guild: guild, created_by: user, status: :in_progress) }
        let!(:participation1) do
          create(:discord_event_participation,
                 event: event,
                 discord_username: "User1#1234",
                 discord_user_id: "user1_id",
                 on_time: true)
        end

        it "does not automatically mark new participations as on_time" do
          participation2 = create(:discord_event_participation,
                                 event: event,
                                 discord_username: "User2#5678",
                                 discord_user_id: "user2_id",
                                 on_time: false)

          expect(participation2.on_time).to be false
        end
      end
    end
  end

  describe "cascade deletions" do
    let(:event) { create(:event, guild: guild, created_by: user) }
    let!(:event_participation) { create(:event_participation, event: event, user: create(:user)) }

    it "deletes associated records when event is deleted" do
      event_id = event.id
      expect(EventParticipation.where(event_id: event_id).count).to eq(1)

      event.destroy

      expect(EventParticipation.where(event_id: event_id).count).to eq(0)
    end
  end

  describe "Discord cleanup on destroy" do
    let(:discord_guild_snowflake) { "987654321098765432" }
    let!(:guild_discord_setting) do
      create(
        :guild_discord_setting,
        guild: guild,
        discord_guild_id: discord_guild_snowflake,
        events_channel_id: "111222333444555666",
        bot_token: "test_bot_token_for_event_destroy"
      )
    end

    it "deletes Discord scheduled event and events-channel message when IDs are present" do
      event = create(
        :event,
        guild: guild,
        created_by: user,
        discord_event_id: "sched_evt_1",
        discord_message_id: "msg_1"
      )

      stub_request(
        :delete,
        "#{DiscordService::DISCORD_API_BASE}/guilds/#{discord_guild_snowflake}/scheduled-events/sched_evt_1"
      ).with(headers: { "Authorization" => "Bot test_bot_token_for_event_destroy" })
        .to_return(status: 204)

      stub_request(
        :delete,
        "#{DiscordService::DISCORD_API_BASE}/channels/111222333444555666/messages/msg_1"
      ).with(headers: { "Authorization" => "Bot test_bot_token_for_event_destroy" })
        .to_return(status: 204)

      expect { event.destroy! }.to change(described_class, :count).by(-1)

      expect(WebMock).to have_requested(
        :delete,
        "#{DiscordService::DISCORD_API_BASE}/guilds/#{discord_guild_snowflake}/scheduled-events/sched_evt_1"
      ).once
      expect(WebMock).to have_requested(
        :delete,
        "#{DiscordService::DISCORD_API_BASE}/channels/111222333444555666/messages/msg_1"
      ).once
    end

    it "still destroys the row when Discord scheduled event delete fails" do
      event = create(
        :event,
        guild: guild,
        created_by: user,
        discord_event_id: "sched_bad",
        discord_message_id: nil
      )

      stub_request(
        :delete,
        "#{DiscordService::DISCORD_API_BASE}/guilds/#{discord_guild_snowflake}/scheduled-events/sched_bad"
      ).to_return(status: 500, body: "error")

      expect { event.destroy! }.to change(described_class, :count).by(-1)
    end

    it "does not issue Discord DELETE requests when artifact IDs are blank" do
      event = create(:event, guild: guild, created_by: user, discord_event_id: nil, discord_message_id: nil)

      event.destroy!

      expect(WebMock).not_to have_requested(:delete, %r{discord\.com/api})
    end
  end
end
