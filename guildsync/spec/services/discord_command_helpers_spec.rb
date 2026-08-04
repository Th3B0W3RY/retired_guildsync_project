# frozen_string_literal: true

require "rails_helper"

# Unit tests for the shared DiscordCommandHelpers module.
# Exercises resolution, permission guards, plan limit enforcement, and
# response builder helpers in isolation by wrapping them in a plain object.
RSpec.describe DiscordCommandHelpers, type: :service do
  # -------------------------------------------------------------------------
  # Wrapper class so we can call the module methods in tests
  # -------------------------------------------------------------------------
  let(:helper) do
    Class.new do
      include DiscordCommandHelpers
      public :resolve_guild_and_user, :require_officer!, :require_owner!,
             :enforce_plan_limit!, :ephemeral_response, :error_response,
             :public_response, :embed_response, :deferred_response,
             :subcommand_name, :subcommand_options, :command_options,
             :build_datetime_from_options
    end.new
  end

  # -------------------------------------------------------------------------
  # Shared factories
  # -------------------------------------------------------------------------
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let!(:discord_setting) do
    create(:guild_discord_setting, guild: guild, discord_guild_id: "server_123")
  end
  let!(:owner_conn) do
    create(:user_discord_connection, user: owner, discord_user_id: "discord_owner_1")
  end
  let(:member_user) { create(:user) }
  let!(:member_conn) do
    create(:user_discord_connection, user: member_user, discord_user_id: "discord_member_1")
  end
  let!(:guild_member_record) do
    guild.guild_members.find_or_create_by!(user: member_user) do |gm|
      gm.role   = :member
      gm.status = :active
    end
  end

  def interaction_for(discord_user_id, guild_id: "server_123")
    {
      "guild_id" => guild_id,
      "member"   => { "user" => { "id" => discord_user_id } }
    }
  end

  # =========================================================================
  describe "#resolve_guild_and_user" do
    context "when guild_id is missing" do
      it "returns an ephemeral error response" do
        result = helper.resolve_guild_and_user({})
        expect(result).to include(type: 4)
        expect(result.dig(:data, :flags)).to eq(64)
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.server_only"))
      end
    end

    context "when guild is not linked to GuildSync" do
      it "returns a not-linked error" do
        result = helper.resolve_guild_and_user(interaction_for("discord_owner_1", guild_id: "unknown_server"))
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.guild_not_linked"))
      end
    end

    context "when Discord user is not linked to GuildSync" do
      it "returns a user-not-linked error" do
        result = helper.resolve_guild_and_user(interaction_for("unknown_discord_user"))
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.user_not_linked"))
      end
    end

    context "when Discord user is not a guild member" do
      let!(:outsider) { create(:user) }
      let!(:outsider_conn) { create(:user_discord_connection, user: outsider, discord_user_id: "discord_outsider") }

      it "returns a not-a-member error" do
        result = helper.resolve_guild_and_user(interaction_for("discord_outsider"))
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.not_a_member"))
      end
    end

    context "with a fully linked active member" do
      it "returns [guild, user, guild_member]" do
        result = helper.resolve_guild_and_user(interaction_for("discord_member_1"))
        expect(result).to be_an(Array)
        expect(result[0]).to eq(guild)
        expect(result[1]).to eq(member_user)
        expect(result[2]).to be_a(GuildMember)
      end
    end
  end

  # =========================================================================
  describe "#require_officer!" do
    let(:officer_user) { create(:user) }
    let!(:officer_conn) { create(:user_discord_connection, user: officer_user, discord_user_id: "discord_officer") }
    let!(:officer_member) do
      guild.guild_members.create!(user: officer_user, role: :moderator, status: :active)
    end

    it "allows access for a moderator" do
      expect(helper.require_officer!(guild, officer_user, officer_member)).to be_nil
    end

    it "allows access for the guild owner" do
      owner_member = guild.guild_members.find_by(user: owner)
      expect(helper.require_officer!(guild, owner, owner_member)).to be_nil
    end

    it "denies access for a plain member" do
      result = helper.require_officer!(guild, member_user, guild_member_record)
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
    end
  end

  # =========================================================================
  describe "#require_owner!" do
    it "allows the guild owner" do
      expect(helper.require_owner!(guild, owner)).to be_nil
    end

    it "denies non-owners" do
      result = helper.require_owner!(guild, member_user)
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.owner_required"))
    end
  end

  # =========================================================================
  describe "response builders" do
    it "#ephemeral_response returns type 4 with flags=64" do
      r = helper.ephemeral_response("test")
      expect(r).to eq(type: 4, data: { content: "test", flags: 64 })
    end

    it "#public_response returns type 4 without flags" do
      r = helper.public_response("hello")
      expect(r).to eq(type: 4, data: { content: "hello" })
    end

    it "#deferred_response returns type 5" do
      r = helper.deferred_response
      expect(r[:type]).to eq(5)
    end
  end

  # =========================================================================
  describe "#enforce_plan_limit!" do
    before do
      # Ensure owner has a plan with limits
      owner.current_plan.update!(max_polls: 5, max_loot_rolls: 3, max_events: 10)
    end

    it "returns nil when under the poll limit" do
      expect(helper.enforce_plan_limit!(guild, :polls)).to be_nil
    end

    it "returns error when at the poll limit" do
      owner.current_plan.update!(max_polls: 1)
      create(:poll, guild: guild, creator: owner, deadline: 1.day.from_now)
      result = helper.enforce_plan_limit!(guild, :polls)
      expect(result.dig(:data, :content)).to include("polls")
    end

    it "returns nil for unlimited plans (limit = 0)" do
      owner.current_plan.update!(max_polls: 0)
      expect(helper.enforce_plan_limit!(guild, :polls)).to be_nil
    end

    it "returns nil for nil limits (unlimited)" do
      owner.current_plan.update!(max_polls: nil)
      expect(helper.enforce_plan_limit!(guild, :polls)).to be_nil
    end

    it "returns error when at the loot_rolls limit" do
      owner.current_plan.update!(max_loot_rolls: 1)
      create(:loot_roll, guild: guild, creator: owner, status: :open)
      result = helper.enforce_plan_limit!(guild, :loot_rolls)
      expect(result.dig(:data, :content)).to include("loot rolls")
    end

    it "returns error when at the events limit" do
      owner.current_plan.update!(max_events: 1)
      conn = create(:discord_connection, guild: guild, user: owner)
      create(:discord_event, guild: guild, discord_connection: conn, scheduled_at: 1.day.from_now)
      result = helper.enforce_plan_limit!(guild, :events)
      expect(result.dig(:data, :content)).to include("events")
    end

    it "returns error when owner has no plan" do
      allow(owner).to receive(:current_plan).and_return(nil)
      # Need to reload guild owner
      allow(guild).to receive_message_chain(:owner, :current_plan).and_return(nil)
      result = helper.enforce_plan_limit!(guild, :polls)
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.no_plan"))
    end
  end

  # =========================================================================
  describe "response builders (extended)" do
    it "#embed_response wraps a single embed hash into an array" do
      r = helper.embed_response({ title: "Test" })
      expect(r.dig(:data, :embeds)).to eq([{ title: "Test" }])
      expect(r.dig(:data, :flags)).to eq(64)
    end

    it "#embed_response passes through an array of embeds" do
      embeds = [{ title: "A" }, { title: "B" }]
      r = helper.embed_response(embeds)
      expect(r.dig(:data, :embeds)).to eq(embeds)
    end

    it "#embed_response with ephemeral: false omits flags" do
      r = helper.embed_response({ title: "Public" }, ephemeral: false)
      expect(r.dig(:data, :flags)).to be_nil
    end

    it "#embed_response includes components when provided" do
      components = [{ type: 1, components: [{ type: 2, label: "Click" }] }]
      r = helper.embed_response({ title: "T" }, components: components)
      expect(r.dig(:data, :components)).to eq(components)
    end

    it "#deferred_response with ephemeral: false omits flags" do
      r = helper.deferred_response(ephemeral: false)
      expect(r[:type]).to eq(5)
      expect(r.dig(:data, :flags)).to be_nil
    end
  end

  # =========================================================================
  describe "#command_options" do
    let(:interaction) do
      {
        "data" => {
          "options" => [
            { "type" => 3, "name" => "query", "value" => "search term" },
            { "type" => 4, "name" => "limit", "value" => 10 }
          ]
        }
      }
    end

    it "extracts top-level options as name -> value hash" do
      opts = helper.command_options(interaction)
      expect(opts["query"]).to eq("search term")
      expect(opts["limit"]).to eq(10)
    end

    it "excludes subcommand options (type 1)" do
      interaction_with_sub = {
        "data" => {
          "options" => [
            { "type" => 1, "name" => "create", "options" => [{ "name" => "title", "value" => "t" }] },
            { "type" => 3, "name" => "query", "value" => "q" }
          ]
        }
      }
      opts = helper.command_options(interaction_with_sub)
      expect(opts).to eq({ "query" => "q" })
    end
  end

  # =========================================================================
  describe "#subcommand_name and #subcommand_options" do
    let(:interaction) do
      {
        "data" => {
          "options" => [
            {
              "type"    => 1,
              "name"    => "create",
              "options" => [
                { "name" => "question", "value" => "Is this a test?" }
              ]
            }
          ]
        }
      }
    end

    it "extracts the subcommand name as symbol" do
      expect(helper.subcommand_name(interaction)).to eq(:create)
    end

    it "extracts subcommand options as name -> value hash" do
      opts = helper.subcommand_options(interaction)
      expect(opts["question"]).to eq("Is this a test?")
    end
  end

  # =========================================================================
  describe "#build_datetime_from_options" do
    let(:next_year) { Time.current.year + 1 }

    # Helper to build a duck-typed guild double with a specific timezone.
    # Defined at the start of the block so all examples can use it.
    def build_guild_with_tz(tz_name)
      instance_double(Guild,
        guild_discord_setting: instance_double(GuildDiscordSetting, default_timezone: tz_name))
    end

    it "builds a valid UTC time from split options (explicit year)" do
      time, error = helper.build_datetime_from_options(
        { month: 6, day: 15, year: next_year, hour: 8, minute: 30, ampm: "PM" }
      )
      expect(error).to be_nil
      expect(time).to be_a(Time)
      expect(time.utc?).to be true
    end

    it "falls back to Eastern when no guild is given" do
      time_eastern, _ = helper.build_datetime_from_options(
        { month: 7, day: 4, year: next_year, hour: 10, minute: 0, ampm: "AM" }
      )
      eastern_tz = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]
      expected   = eastern_tz.local(next_year, 7, 4, 10, 0).utc
      expect(time_eastern).to eq(expected)
    end

    it "uses the guild's configured default_timezone" do
      discord_setting.update!(default_timezone: "Pacific Time (US & Canada)")

      time_pacific, _ = helper.build_datetime_from_options(
        { month: 7, day: 4, year: next_year, hour: 10, minute: 0, ampm: "AM" },
        guild: guild
      )
      pacific_tz = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
      expected   = pacific_tz.local(next_year, 7, 4, 10, 0).utc
      expect(time_pacific).to eq(expected)
    end

    it "defaults year to current year and returns a future time" do
      future_month = (Time.current.month % 12) + 1
      time, error = helper.build_datetime_from_options(
        { month: future_month, day: 15, hour: 3, minute: 0, ampm: "PM" }
      )
      expect(error).to be_nil
      expect(time).to be > Time.current
    end

    it "auto-bumps to next year when the current-year date is in the past" do
      time, error = helper.build_datetime_from_options(
        { month: 1, day: 1, hour: 12, minute: 0, ampm: "AM" }
      )
      expect(error).to be_nil
      expect(time).to be > Time.current
    end

    it "converts 12 AM correctly to midnight" do
      time, _ = helper.build_datetime_from_options(
        { month: 6, day: 15, year: next_year, hour: 12, minute: 0, ampm: "AM" },
        guild: build_guild_with_tz("UTC")
      )
      expect(time.utc.hour).to eq(0)
    end

    it "converts 12 PM correctly to noon" do
      time, _ = helper.build_datetime_from_options(
        { month: 6, day: 15, year: next_year, hour: 12, minute: 0, ampm: "PM" },
        guild: build_guild_with_tz("UTC")
      )
      expect(time.utc.hour).to eq(12)
    end

    it "returns error for invalid month" do
      _, error = helper.build_datetime_from_options(
        { month: 13, day: 1, hour: 1, minute: 0, ampm: "AM" }
      )
      expect(error).to include(I18n.t("discord.commands.datetime.invalid_month"))
    end

    it "returns error for invalid day (Feb 30)" do
      _, error = helper.build_datetime_from_options(
        { month: 2, day: 30, year: next_year, hour: 1, minute: 0, ampm: "AM" }
      )
      expect(error).to include("February")
    end

    it "returns error for explicitly past dates (year provided)" do
      _, error = helper.build_datetime_from_options(
        { month: 1, day: 1, year: 2000, hour: 12, minute: 0, ampm: "AM" }
      )
      expect(error).to include(I18n.t("discord.commands.datetime.in_the_past"))
    end

    it "returns error for invalid ampm" do
      _, error = helper.build_datetime_from_options(
        { month: 6, day: 15, year: next_year, hour: 8, minute: 0, ampm: "XM" }
      )
      expect(error).to include(I18n.t("discord.commands.datetime.invalid_time"))
    end

    it "returns error for hour out of 1-12 range" do
      _, error = helper.build_datetime_from_options(
        { month: 6, day: 15, year: next_year, hour: 0, minute: 0, ampm: "AM" }
      )
      expect(error).to include(I18n.t("discord.commands.datetime.invalid_time"))
    end

    it "accepts Feb 29 on a leap year" do
      leap_year = next_year.upto(next_year + 4).find { |y| Date.leap?(y) }
      time, error = helper.build_datetime_from_options(
        { month: 2, day: 29, year: leap_year, hour: 6, minute: 0, ampm: "PM" },
        guild: build_guild_with_tz("UTC")
      )
      expect(error).to be_nil
      expect(time.day).to eq(29)
    end

    it "rejects Feb 29 on a non-leap year" do
      non_leap = next_year.upto(next_year + 4).find { |y| !Date.leap?(y) }
      _, error = helper.build_datetime_from_options(
        { month: 2, day: 29, year: non_leap, hour: 6, minute: 0, ampm: "PM" }
      )
      expect(error).to include("February")
    end

    it "rejects day 0" do
      _, error = helper.build_datetime_from_options(
        { month: 6, day: 0, year: next_year, hour: 6, minute: 0, ampm: "PM" }
      )
      expect(error).to include(I18n.t("discord.commands.datetime.invalid_day", max: 30, month: "June"))
    end

    it "falls back to Eastern for an unrecognised guild timezone" do
      bad_guild = build_guild_with_tz("Not A Real Timezone")
      time_bad, _ = helper.build_datetime_from_options(
        { month: 6, day: 15, year: next_year, hour: 3, minute: 0, ampm: "PM" },
        guild: bad_guild
      )
      eastern  = ActiveSupport::TimeZone["Eastern Time (US & Canada)"]
      expected = eastern.local(next_year, 6, 15, 15, 0).utc
      expect(time_bad).to eq(expected)
    end

    it "handles lowercase ampm" do
      time, error = helper.build_datetime_from_options(
        { month: 6, day: 15, year: next_year, hour: 3, minute: 0, ampm: "pm" },
        guild: build_guild_with_tz("UTC")
      )
      expect(error).to be_nil
      expect(time.utc.hour).to eq(15)
    end

  end
end
