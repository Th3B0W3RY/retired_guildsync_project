# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordEventCommandService, type: :service do
  include_context "Discord API stubs"

  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner) }
  let!(:discord_setting) do
    create(:guild_discord_setting, guild: guild, discord_guild_id: "svr_event",
           events_channel_id: "chan_events")
  end
  let!(:owner_conn)   { create(:user_discord_connection, user: owner, discord_user_id: "d_owner_e") }
  let(:officer_user)  { create(:user) }
  let!(:officer_conn) { create(:user_discord_connection, user: officer_user, discord_user_id: "d_officer_e") }
  let!(:officer_member) { guild.guild_members.create!(user: officer_user, role: :admin, status: :active) }
  let(:member_user)   { create(:user) }
  let!(:member_conn)  { create(:user_discord_connection, user: member_user, discord_user_id: "d_member_e") }
  let!(:guild_member_record) { guild.guild_members.create!(user: member_user, role: :member, status: :active) }

  before do
    # Broader stubs to cover non-numeric guild IDs and any bot token
    stub_request(:get, %r{https://discord\.com/api/v10/guilds/.+/scheduled-events})
      .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{https://discord\.com/api/v10/guilds/.+$})
      .to_return(status: 200, body: { id: "svr_event", name: "Test Server" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:post, %r{https://discord\.com/api/v10/guilds/.+/scheduled-events})
      .to_return(status: 200, body: { id: "fake_scheduled_event_id" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:post, %r{https://discord\.com/api/v10/channels/.+/messages})
      .to_return(status: 200, body: { id: "fake_message_id" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:delete, %r{https://discord\.com/api/v10/guilds/.+/scheduled-events/.+})
      .to_return(status: 204, body: "", headers: {})
    stub_request(:delete, %r{https://discord\.com/api/v10/channels/.+/messages/.+})
      .to_return(status: 204, body: "", headers: {})
  end

  def build_interaction(discord_user_id, subcommand:, options: [])
    {
      "guild_id" => "svr_event",
      "token"    => "test_token_event",
      "member"   => { "user" => { "id" => discord_user_id } },
      "data"     => {
        "name"    => "event",
        "options" => [
          { "type" => 1, "name" => subcommand.to_s, "options" => options }
        ]
      }
    }
  end

  describe "/event list" do
    it "returns none_upcoming when no upcoming events" do
      result = described_class.handle(build_interaction("d_member_e", subcommand: :list))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.event.none_upcoming"))
    end

    it "lists upcoming events" do
      conn  = create(:discord_connection, guild: guild, user: owner)
      event = create(:discord_event, guild: guild, discord_connection: conn,
                     title: "Big Battle", scheduled_at: 2.days.from_now)
      result = described_class.handle(build_interaction("d_member_e", subcommand: :list))
      expect(result.dig(:data, :embeds, 0, :description)).to include("Big Battle")
    end
  end

  describe "/event view" do
    it "returns not_found for invalid event_id" do
      result = described_class.handle(build_interaction("d_member_e", subcommand: :view,
                                                        options: [{ "name" => "event_id", "value" => 9_999_999 }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.event.not_found"))
    end

    it "returns embed for valid event_id" do
      conn  = create(:discord_connection, guild: guild, user: owner)
      event = create(:discord_event, guild: guild, discord_connection: conn,
                     title: "Guild War", scheduled_at: 3.days.from_now)
      result = described_class.handle(build_interaction("d_member_e", subcommand: :view,
                                                        options: [{ "name" => "event_id", "value" => event.id }]))
      expect(result.dig(:data, :embeds, 0, :title)).to include("Guild War")
    end
  end

  describe "/event create" do
    let(:future_time) { 5.days.from_now.in_time_zone("Eastern Time (US & Canada)") }
    let(:create_opts) do
      [
        { "name" => "title",  "value" => "Raid Night" },
        { "name" => "month",  "value" => future_time.month },
        { "name" => "day",    "value" => future_time.day },
        { "name" => "hour",   "value" => ((h = future_time.hour % 12) == 0 ? 12 : h) },
        { "name" => "minute", "value" => (future_time.min / 5) * 5 },
        { "name" => "ampm",   "value" => future_time.hour < 12 ? "AM" : "PM" }
      ]
    end

    it "returns deferred for officer" do
      result = described_class.handle(build_interaction("d_officer_e", subcommand: :create, options: create_opts))
      expect(result[:type]).to eq(5)
    end

    it "returns officer_required for plain member" do
      result = described_class.handle(build_interaction("d_member_e", subcommand: :create, options: create_opts))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
    end

    it "returns missing_title when title is absent" do
      opts = create_opts.reject { |o| o["name"] == "title" }
      result = described_class.handle(build_interaction("d_officer_e", subcommand: :create, options: opts))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.event.missing_title"))
    end

    it "returns invalid_day for February 30" do
      bad_day_opts = [
        { "name" => "title",  "value" => "Bad Day" },
        { "name" => "month",  "value" => 2 },
        { "name" => "day",    "value" => 30 },
        { "name" => "hour",   "value" => 8 },
        { "name" => "minute", "value" => 0 },
        { "name" => "ampm",   "value" => "PM" }
      ]
      result = described_class.handle(build_interaction("d_officer_e", subcommand: :create, options: bad_day_opts))
      expect(result.dig(:data, :content)).to include("February")
    end

    it "uses the guild's default_timezone for scheduling" do
      discord_setting.update!(default_timezone: "Pacific Time (US & Canada)")
      result = described_class.handle(build_interaction("d_officer_e", subcommand: :create, options: create_opts))
      expect(result[:type]).to eq(5)
    end

    it "returns no_channel when events channel is not configured" do
      discord_setting.update!(events_channel_id: nil)
      result = described_class.handle(build_interaction("d_officer_e", subcommand: :create, options: create_opts))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.event.no_channel"))
    end

    it "returns plan_limit when event cap is reached" do
      owner.current_plan.update!(max_events: 1)
      conn = create(:discord_connection, guild: guild, user: owner)
      create(:discord_event, guild: guild, discord_connection: conn, scheduled_at: 1.day.from_now)

      result = described_class.handle(build_interaction("d_officer_e", subcommand: :create, options: create_opts))

      expect(result.dig(:data, :content)).to include(
        I18n.t("discord.commands.errors.plan_limit",
               feature: "events", limit: 1, plan: owner.current_plan.name)
      )
    end
  end

  describe "/event cancel" do
    it "returns officer_required for plain member" do
      result = described_class.handle(build_interaction("d_member_e", subcommand: :cancel,
                                                        options: [{ "name" => "event_id", "value" => 1 }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
    end

    it "returns not_found for non-existent event" do
      result = described_class.handle(build_interaction("d_officer_e", subcommand: :cancel,
                                                        options: [{ "name" => "event_id", "value" => 9_999_999 }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.event.not_found"))
    end
  end

  # =========================================================================
  # process_cancel idempotency (called by DiscordCommandJob)
  # =========================================================================
  describe "#process_cancel" do
    let(:service) { described_class.new }
    let(:conn)    { create(:discord_connection, guild: guild, user: owner) }
    let!(:event)  do
      create(:discord_event, guild: guild, discord_connection: conn,
             title: "Raid Night", scheduled_at: 2.days.from_now)
    end

    before do
      service.instance_variable_set(:@guild, guild)
      service.instance_variable_set(:@user, officer_user)
      service.instance_variable_set(:@interaction_token, "tok_cancel_event")
      service.instance_variable_set(:@guild_member, officer_member)

      stub_request(:post, %r{discord\.com/api/v10/webhooks/.+}).to_return(status: 200, body: "{}")
    end

    it "destroys the event on first call" do
      service.send(:process_cancel, { event_id: event.id }.with_indifferent_access)
      expect(guild.discord_events.find_by(id: event.id)).to be_nil
    end

    it "gracefully handles already-destroyed event (idempotent)" do
      event.destroy

      expect {
        service.send(:process_cancel, { event_id: event.id }.with_indifferent_access)
      }.not_to raise_error
    end
  end
end
