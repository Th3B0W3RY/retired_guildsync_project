# frozen_string_literal: true

require 'rails_helper'
require 'rbnacl'

RSpec.describe "Discord Webhooks Interactions", type: :request do
  # Test data
  let(:user) { create(:user) }
  let(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:subscription) { create(:subscription, user: user, pricing_plan: pricing_plan) }
  let(:guild) { create(:guild, owner: user) }
  let(:discord_connection) { create(:discord_connection, guild: guild, user: user) }
  let(:discord_event) { create(:discord_event, guild: guild, discord_connection: discord_connection) }

  # Discord interaction data
  let(:fake_discord_user_id) { "123456789012345678" }
  let(:fake_discord_username) { "TestUser" }
  let(:fake_discord_discriminator) { "1234" }
  let(:fake_interaction_token) { SecureRandom.hex(32) }
  let(:fake_interaction_id) { SecureRandom.hex(16) }

  # Discord signature setup
  let(:public_key_hex) { ENV["DISCORD_PUBLIC_KEY"] || "a" * 64 } # Fallback for testing
  let(:private_key) { RbNaCl::SigningKey.generate }
  let(:verify_key) { private_key.verify_key }

  # Helper to generate valid Discord signature
  def generate_discord_signature(timestamp, body)
    message = "#{timestamp}#{body}"
    signature = private_key.sign(message)
    signature.unpack1("H*")
  end

  # Helper to create a valid Discord interaction request
  def create_interaction_request(interaction_data, skip_signature: false)
    body = interaction_data.to_json
    timestamp = Time.now.to_i.to_s

    if skip_signature || Rails.env.test?
      signature = "0" * 128 # Fake signature for test env
    else
      signature = generate_discord_signature(timestamp, body)
    end

    {
      body: body,
      headers: {
        "X-Signature-Ed25519" => signature,
        "X-Signature-Timestamp" => timestamp,
        "Content-Type" => "application/json"
      }
    }
  end

  # Helper to create button click interaction
  def create_button_interaction(custom_id, member_data = nil)
    member_data ||= {
      "user" => {
        "id" => fake_discord_user_id,
        "username" => fake_discord_username,
        "discriminator" => fake_discord_discriminator,
        "global_name" => nil
      }
    }

    {
      "type" => 3, # MESSAGE_COMPONENT
      "token" => fake_interaction_token,
      "id" => fake_interaction_id,
      "data" => {
        "custom_id" => custom_id,
        "component_type" => 2
      },
      "member" => member_data,
      "guild_id" => "987654321098765432",
      "channel_id" => discord_event.channel_id
    }
  end

  include_context "Discord API stubs"

  before do
    # Mock signature verification to allow test requests
    allow_any_instance_of(DiscordWebhooksController).to receive(:verify_discord_signature).and_return(true)

    # Mock DiscordService to avoid actual API calls
    discord_service = instance_double(DiscordService)
    allow(DiscordService).to receive(:new).and_return(discord_service)
    allow(discord_service).to receive(:update_message).and_return(true)

    # RSVP interactions now require a linked GuildSync account + active guild membership.
    unless UserDiscordConnection.exists?(discord_user_id: fake_discord_user_id)
      create(
        :user_discord_connection,
        user: user,
        discord_user_id: fake_discord_user_id,
        discord_username: "#{fake_discord_username}##{fake_discord_discriminator}"
      )
    end
    create(:guild_member, guild: guild, user: user, status: :active) unless guild.guild_members.exists?(user: user)
  end

  describe "POST /discord/webhooks - Button Click Interactions" do
    context "event_signup button clicks" do
      it "responds within 3 seconds and processes signup correctly" do
        # Create interaction for DPS role signup
        interaction = create_button_interaction("event_signup_#{discord_event.id}_dps")
        request_data = create_interaction_request(interaction)

        start_time = Time.now

        post "/discord/webhooks",
             params: request_data[:body],
             headers: request_data[:headers]

        end_time = Time.now
        response_time = (end_time - start_time) * 1000 # Convert to milliseconds

        # Verify response is fast (< 3 seconds = 3000ms)
        expect(response_time).to be < 3000

        # Verify response is correct
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["type"]).to eq(5) # DEFERRED_UPDATE_MESSAGE
      end

      it "handles all role types correctly" do
        DiscordEvent::ROLE_CATEGORIES.each do |role|
          interaction = create_button_interaction("event_signup_#{discord_event.id}_#{role}")
          request_data = create_interaction_request(interaction)

          post "/discord/webhooks",
               params: request_data[:body],
               headers: request_data[:headers]

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response["type"]).to eq(5)
        end
      end

      it "cycles through statuses when clicking same button multiple times" do
        # In the current implementation, event_signup buttons open an attendance
        # selection menu, and status changes are handled via separate
        # `event_status_...` buttons. This test now verifies that cycling through
        # those status buttons updates the signup record correctly.

        # First click - on_time (creates signup)
        on_time_interaction = create_button_interaction(
          "event_status_#{discord_event.id}_dps_on_time_#{fake_discord_user_id}"
        )
        on_time_request = create_interaction_request(on_time_interaction)

        post "/discord/webhooks",
             params: on_time_request[:body],
             headers: on_time_request[:headers]
        sleep(0.3)

        signup = discord_event.discord_event_signups.find_by(
          discord_user_id: fake_discord_user_id
        )
        expect(signup).to be_present
        expect(signup.role).to eq("dps")
        expect(signup.status).to eq("on_time")

        # Second click - late
        late_interaction = create_button_interaction(
          "event_status_#{discord_event.id}_dps_late_#{fake_discord_user_id}"
        )
        late_request = create_interaction_request(late_interaction)

        post "/discord/webhooks",
             params: late_request[:body],
             headers: late_request[:headers]
        sleep(0.3)

        signup.reload
        expect(signup.status).to eq("late")

        # Third click - absent
        absent_interaction = create_button_interaction(
          "event_status_#{discord_event.id}_dps_absent_#{fake_discord_user_id}"
        )
        absent_request = create_interaction_request(absent_interaction)

        post "/discord/webhooks",
             params: absent_request[:body],
             headers: absent_request[:headers]
        sleep(0.3)

        signup.reload
        expect(signup.status).to eq("absent")

        # Fourth click - remove (deletes signup)
        remove_interaction = create_button_interaction(
          "event_status_#{discord_event.id}_dps_remove_#{fake_discord_user_id}"
        )
        remove_request = create_interaction_request(remove_interaction)

        post "/discord/webhooks",
             params: remove_request[:body],
             headers: remove_request[:headers]
        sleep(0.3)

        expect(
          discord_event.discord_event_signups.find_by(
            discord_user_id: fake_discord_user_id
          )
        ).to be_nil
      end
    end

    context "RSVP follow-up and event embed i18n (discord.webhooks.rsvp / event_embed)" do
      it "defines nested webhook copy for every configured locale" do
        I18n.available_locales.each do |locale|
          I18n.with_locale(locale) do
            expect(I18n.t("discord.webhooks.rsvp.attendance_prompt", role: "DPS")).to be_present
            expect(I18n.t("discord.webhooks.alliance_rsvp.attendance_prompt", role: "HEALER")).to be_present
            expect(I18n.t("discord.webhooks.event_embed.signup_prompt")).to be_present
            expect(I18n.t("discord.webhooks.event_embed.footer")).to be_present
            expect(I18n.t("discord.webhooks.rsvp.status_labels.on_time")).to be_present
            expect(
              I18n.t(
                "discord.webhooks.legacy_event_details.scheduled_block",
                date_stamp: "<t:0:D>",
                time_stamp: "<t:0:t>"
              )
            ).to be_present
            expect(I18n.t("discord.webhooks.legacy_event_details.participants_line", count: 3)).to be_present
          end
        end
      end
    end

    context "legacy Event model event_details button" do
      let(:legacy_event) do
        create(
          :event,
          guild: guild,
          created_by: user,
          title: "Maple Raid",
          description: "Bring pots.",
          scheduled_at: 2.days.from_now.change(hour: 18, min: 0),
          duration: 90,
          location: "North Gate",
          squad_leader: "LeadPlayer"
        )
      end

      it "returns type 4 ephemeral copy with i18n field labels" do
        ev = legacy_event
        interaction = create_button_interaction("event_details_#{ev.id}")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks",
             params: request_data[:body],
             headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
        expect(json["data"]["flags"]).to eq(64)
        content = json["data"]["content"]
        expect(content).to include("**Maple Raid**")
        expect(content).to include("Bring pots.")
        expect(content).to include(
          I18n.t(
            "discord.webhooks.legacy_event_details.scheduled_block",
            date_stamp: "<t:#{ev.scheduled_at.to_i}:D>",
            time_stamp: "<t:#{ev.scheduled_at.to_i}:t>"
          )
        )
        expect(content).to include(I18n.t("discord.webhooks.legacy_event_details.duration_line", minutes: 90))
        expect(content).to include(I18n.t("discord.webhooks.legacy_event_details.location_line", value: "North Gate"))
        expect(content).to include(I18n.t("discord.webhooks.legacy_event_details.squad_leader_line", value: "LeadPlayer"))
        expect(content).to include(I18n.t("discord.webhooks.legacy_event_details.participants_line", count: 0))
      end
    end

    context "PING requests" do
      it "responds immediately with PONG" do
        ping_interaction = { "type" => 1 }
        request_data = create_interaction_request(ping_interaction)

        start_time = Time.now

        post "/discord/webhooks",
             params: request_data[:body],
             headers: request_data[:headers]

        end_time = Time.now
        response_time = (end_time - start_time) * 1000

        # PING should be very fast (< 100ms)
        expect(response_time).to be < 100

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["type"]).to eq(1) # PONG
      end
    end

    context "signature verification" do
      it "returns ephemeral invalid_signature and does not answer PING when verification fails" do
        allow_any_instance_of(DiscordWebhooksController).to receive(:verify_discord_signature).and_return(false)

        ping_interaction = { "type" => 1 }
        request_data = create_interaction_request(ping_interaction)

        post "/discord/webhooks",
             params: request_data[:body],
             headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["type"]).to eq(4)
        expect(json_response["data"]["flags"]).to eq(64)
        expect(json_response["data"]["content"]).to eq(I18n.t("discord.webhooks.invalid_signature"))
      end
    end

    context "Slash Command routing" do
      let!(:discord_setting) { create(:guild_discord_setting, guild: guild, discord_guild_id: "987654321098765432") }
      let!(:user_conn) do
        UserDiscordConnection.find_by(discord_user_id: fake_discord_user_id) ||
          create(
            :user_discord_connection,
            user: user,
            discord_user_id: fake_discord_user_id,
            discord_username: "#{fake_discord_username}##{fake_discord_discriminator}"
          )
      end
      let!(:guild_member) { guild.guild_members.find_by(user: user) || create(:guild_member, guild: guild, user: user, role: :owner) }

      def create_command_interaction(name, subcommand = nil, options = [])
        data = { "name" => name }
        if subcommand
          data["options"] = [{ "type" => 1, "name" => subcommand, "options" => options }]
        else
          data["options"] = options
        end

        {
          "type" => 2, # APPLICATION_COMMAND
          "token" => fake_interaction_token,
          "id" => fake_interaction_id,
          "data" => data,
          "member" => {
            "user" => {
              "id" => fake_discord_user_id,
              "username" => fake_discord_username
            }
          },
          "guild_id" => "987654321098765432"
        }
      end

      it "routes /poll list correctly" do
        interaction = create_command_interaction("poll", "list")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4) # Immediate response
      end

      it "routes /loot list correctly" do
        interaction = create_command_interaction("loot", "list")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end

      it "routes /event list correctly" do
        interaction = create_command_interaction("event", "list")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end

      it "routes /invite correctly" do
        target_user = create(:user)
        create(:user_discord_connection, user: target_user, discord_user_id: "target_id")
        
        interaction = create_command_interaction("invite", nil, [{ "name" => "user", "value" => "target_id" }])
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(5) # Deferred
      end

      it "routes /member list correctly" do
        interaction = create_command_interaction("member", "list")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end

      it "routes /guild info correctly" do
        interaction = create_command_interaction("guild", "info")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end

      it "routes /application list correctly" do
        interaction = create_command_interaction("application", "list")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end

      it "routes /docs list correctly" do
        interaction = create_command_interaction("docs", "list")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end

      it "routes /leaderboard correctly" do
        interaction = create_command_interaction("leaderboard")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end

      it "routes /activity correctly" do
        interaction = create_command_interaction("activity")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end

      it "routes /profile me correctly" do
        interaction = create_command_interaction("profile", "me")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end

      it "routes /help correctly" do
        interaction = create_command_interaction("help")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks", params: request_data[:body], headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq(4)
      end
    end

    context "error handling" do
      it "returns valid interaction response for invalid event_id" do
        interaction = create_button_interaction("event_signup_999999_dps")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks",
             params: request_data[:body],
             headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["type"]).to eq(5) # Still returns deferred response
      end

      it "returns valid interaction response for invalid custom_id format" do
        interaction = create_button_interaction("invalid_format_123")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks",
             params: request_data[:body],
             headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["type"]).to eq(4) # Error response
        expect(json_response["data"]["flags"]).to eq(64) # Ephemeral
        expect(json_response["data"]["content"]).to eq(I18n.t("discord.webhooks.unknown_interaction_type"))
      end
    end

    context "poll and loot button dispatch" do
      it "dispatches poll vote interactions to DiscordInteractionJob" do
        allow(DiscordInteractionJob).to receive(:perform_now)

        interaction = create_button_interaction("poll_vote_123_yes")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks",
             params: request_data[:body],
             headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["type"]).to eq(5)
        expect(DiscordInteractionJob).to have_received(:perform_now).with(
          "poll_vote_123_yes",
          fake_interaction_token,
          anything,
          hash_including("data" => hash_including("custom_id" => "poll_vote_123_yes"))
        )
      end

      it "dispatches loot roll interactions to DiscordInteractionJob" do
        allow(DiscordInteractionJob).to receive(:perform_now)

        interaction = create_button_interaction("loot_roll_321_roll")
        request_data = create_interaction_request(interaction)

        post "/discord/webhooks",
             params: request_data[:body],
             headers: request_data[:headers]

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["type"]).to eq(5)
        expect(DiscordInteractionJob).to have_received(:perform_now).with(
          "loot_roll_321_roll",
          fake_interaction_token,
          anything,
          hash_including("data" => hash_including("custom_id" => "loot_roll_321_roll"))
        )
      end
    end
  end

  describe "Stress test - 10 consecutive requests" do
    it "handles 10 rapid button clicks without errors" do
      interaction = create_button_interaction("event_signup_#{discord_event.id}_dps")
      request_data = create_interaction_request(interaction)

      response_times = []
      errors = []

      10.times do |i|
        start_time = Time.now

        begin
          post "/discord/webhooks",
               params: request_data[:body],
               headers: request_data[:headers]

          end_time = Time.now
          response_time = (end_time - start_time) * 1000
          response_times << response_time

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response["type"]).to eq(5)

          # Small delay between requests to avoid overwhelming
          sleep(0.1)
        rescue => e
          errors << { iteration: i + 1, error: e.message }
        end
      end

      # Wait for all background threads to complete
      sleep(1)

      # Verify no errors occurred
      expect(errors).to be_empty

      # Verify all responses were fast
      response_times.each do |time|
        expect(time).to be < 3000, "Response took #{time}ms, exceeding 3 second limit"
      end

      # Verify average response time is reasonable
      avg_time = response_times.sum / response_times.length
      expect(avg_time).to be < 500, "Average response time #{avg_time}ms is too slow"
      # After the rapid signup clicks, simulate the user choosing a status
      # via the event_status button to ensure the full flow still works.
      status_interaction = create_button_interaction(
        "event_status_#{discord_event.id}_dps_on_time_#{fake_discord_user_id}"
      )
      status_request = create_interaction_request(status_interaction)

      post "/discord/webhooks",
           params: status_request[:body],
           headers: status_request[:headers]
      expect(response).to have_http_status(:success)

      # Wait briefly for background processing
      sleep(0.3)

      # Verify signup was created/updated correctly
      signup = discord_event.discord_event_signups.find_by(
        discord_user_id: fake_discord_user_id
      )
      expect(signup).to be_present
    end
  end

  describe "Multiple users signing up simultaneously" do
    it "handles concurrent signups from different users" do
      # Use a small set of IDs without underscores so they parse cleanly from
      # custom_id, matching real Discord snowflake IDs (which are numeric).
      user_ids = (1..3).map { |n| "user#{n}#{SecureRandom.hex(8)}" }

      # RSVP handlers require linked accounts and active guild membership.
      user_ids.each do |user_id|
        u = create(:user, auth_method: :discord)
        create(:user_discord_connection, user: u, discord_user_id: user_id, discord_username: "User#{user_id}#1234")
        create(:guild_member, guild: guild, user: u, status: :active)
      end

      threads = user_ids.map do |user_id|
        Thread.new do
          member_data = {
            "user" => {
              "id" => user_id,
              "username" => "User#{user_id}",
              "discriminator" => "1234",
              "global_name" => nil
            }
          }

          # First: event_signup click (opens attendance selection)
          signup_interaction = create_button_interaction("event_signup_#{discord_event.id}_dps", member_data)
          signup_request = create_interaction_request(signup_interaction)

          post "/discord/webhooks",
               params: signup_request[:body],
               headers: signup_request[:headers]

          expect(response).to have_http_status(:success)

          # Then: status selection (creates signup)
          status_interaction = create_button_interaction(
            "event_status_#{discord_event.id}_dps_on_time_#{user_id}",
            member_data
          )
          status_request = create_interaction_request(status_interaction)

          post "/discord/webhooks",
               params: status_request[:body],
               headers: status_request[:headers]

          expect(response).to have_http_status(:success)
        end
      end

      threads.each(&:join)
      sleep(1) # Wait for background processing

      # Verify all signups were created
      user_ids.each do |user_id|
        signup = discord_event.discord_event_signups.find_by(
          discord_user_id: user_id,
          role: "dps"
        )
        expect(signup).to be_present, "Signup for user #{user_id} was not created"
      end
    end
  end
end
