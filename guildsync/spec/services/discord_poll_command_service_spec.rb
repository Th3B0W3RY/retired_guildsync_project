# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordPollCommandService, type: :service do
  include_context "Discord API stubs"

  # -------------------------------------------------------------------------
  # Shared setup
  # -------------------------------------------------------------------------
  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner) }
  let!(:discord_setting) do
    create(:guild_discord_setting, guild: guild, discord_guild_id: "svr_poll",
           polls_channel_id: "chan_polls")
  end
  let!(:owner_conn)   { create(:user_discord_connection, user: owner, discord_user_id: "d_owner") }
  let(:officer_user)  { create(:user) }
  let!(:officer_conn) { create(:user_discord_connection, user: officer_user, discord_user_id: "d_officer") }
  let!(:officer_member) { guild.guild_members.create!(user: officer_user, role: :moderator, status: :active) }
  let(:member_user)   { create(:user) }
  let!(:member_conn)  { create(:user_discord_connection, user: member_user, discord_user_id: "d_member") }
  let!(:guild_member_record) { guild.guild_members.create!(user: member_user, role: :member, status: :active) }

  before do
    stub_request(:post, %r{https://discord\.com/api/v10/channels/.+/messages})
      .to_return(status: 200, body: { id: "fake_message_id" }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def build_interaction(discord_user_id, subcommand:, options: [])
    {
      "guild_id" => "svr_poll",
      "token"    => "test_token_poll",
      "member"   => { "user" => { "id" => discord_user_id } },
      "data"     => {
        "name"    => "poll",
        "options" => [
          { "type" => 1, "name" => subcommand.to_s, "options" => options }
        ]
      }
    }
  end

  # =========================================================================
  describe "/poll list" do
    context "when there are active polls" do
      let!(:open_poll) do
        create(:poll, guild: guild, title: "Test Poll", deadline: 2.days.from_now, creator: owner)
      end

      it "returns an embed with the poll listed" do
        interaction = build_interaction("d_member", subcommand: :list)
        result = described_class.handle(interaction)
        expect(result[:type]).to eq(4)
        expect(result.dig(:data, :flags)).to eq(64)
        expect(result.dig(:data, :embeds, 0, :description)).to include("Test Poll")
      end
    end

    context "when there are no active polls" do
      it "returns an ephemeral message" do
        interaction = build_interaction("d_member", subcommand: :list)
        result = described_class.handle(interaction)
        expect(result[:type]).to eq(4)
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.poll.none_active"))
      end
    end
  end

  # =========================================================================
  describe "/poll results" do
    let!(:poll) { create(:poll, guild: guild, deadline: 2.days.from_now, creator: owner) }

    it "returns vote results for a valid poll_id" do
      interaction = build_interaction("d_member", subcommand: :results,
                                     options: [{ "name" => "poll_id", "value" => poll.id }])
      result = described_class.handle(interaction)
      expect(result[:type]).to eq(4)
      expect(result.dig(:data, :embeds, 0, :title)).to include(poll.title)
    end

    it "returns not_found error for an invalid poll_id" do
      interaction = build_interaction("d_member", subcommand: :results,
                                     options: [{ "name" => "poll_id", "value" => 9_999_999 }])
      result = described_class.handle(interaction)
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.poll.not_found"))
    end
  end

  # =========================================================================
  describe "/poll create" do
    let(:create_opts) do
      [
        { "name" => "question",  "value" => "Best game?" },
        { "name" => "option_a",  "value" => "Alpha" },
        { "name" => "option_b",  "value" => "Beta" },
        { "name" => "deadline_hours", "value" => 24 }
      ]
    end

    context "when invoked by an officer" do
      it "returns a deferred response" do
        interaction = build_interaction("d_officer", subcommand: :create, options: create_opts)
        result = described_class.handle(interaction)
        expect(result[:type]).to eq(5)
      end
    end

    context "when invoked by a plain member" do
      it "returns an officer_required error" do
        interaction = build_interaction("d_member", subcommand: :create, options: create_opts)
        result = described_class.handle(interaction)
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
      end
    end

    context "when polls channel is not configured" do
      before { discord_setting.update!(polls_channel_id: nil) }

      it "returns a no_channel error" do
        interaction = build_interaction("d_officer", subcommand: :create, options: create_opts)
        result = described_class.handle(interaction)
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.poll.no_channel"))
      end
    end

    context "when required fields are missing" do
      it "returns a missing_fields error" do
        interaction = build_interaction("d_officer", subcommand: :create, options: [])
        result = described_class.handle(interaction)
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.poll.missing_fields"))
      end
    end
  end

  # =========================================================================
  # process_create (called by DiscordCommandJob)
  # =========================================================================
  describe "#process_create" do
    let(:service) { described_class.new }

    before do
      service.instance_variable_set(:@guild, guild)
      service.instance_variable_set(:@user, officer_user)
      service.instance_variable_set(:@interaction_token, "tok_poll_create")
      service.instance_variable_set(:@guild_member, officer_member)

      stub_request(:post, %r{discord\.com/api/v10/webhooks/.+}).to_return(status: 200, body: "{}")
      allow_any_instance_of(DiscordPollService).to receive(:post_poll)
    end

    it "creates a poll record" do
      expect {
        service.send(:process_create, {
          question: "Best class?",
          description: "**A:** Warrior (Yes)\n**B:** Mage (No)",
          deadline: 24.hours.from_now.to_s,
          anonymous: false
        }.with_indifferent_access)
      }.to change(guild.polls, :count).by(1)
    end

    it "sends a follow-up message" do
      service.send(:process_create, {
        question: "Best class?",
        description: "**A:** Warrior (Yes)\n**B:** Mage (No)",
        deadline: 24.hours.from_now.to_s,
        anonymous: false
      }.with_indifferent_access)

      expect(WebMock).to have_requested(:post, %r{discord\.com/api/v10/webhooks})
    end
  end
end
