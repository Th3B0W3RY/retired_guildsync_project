# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordLootCommandService, type: :service do
  include_context "Discord API stubs"

  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner) }
  let!(:discord_setting) do
    create(:guild_discord_setting, guild: guild, discord_guild_id: "svr_loot",
           loot_rolls_channel_id: "chan_loot")
  end
  let!(:owner_conn)   { create(:user_discord_connection, user: owner, discord_user_id: "d_owner_l") }
  let(:officer_user)  { create(:user) }
  let!(:officer_conn) { create(:user_discord_connection, user: officer_user, discord_user_id: "d_officer_l") }
  let!(:officer_member) { guild.guild_members.create!(user: officer_user, role: :moderator, status: :active) }
  let(:member_user)   { create(:user) }
  let!(:member_conn)  { create(:user_discord_connection, user: member_user, discord_user_id: "d_member_l") }
  let!(:guild_member_record) { guild.guild_members.create!(user: member_user, role: :member, status: :active) }

  before do
    stub_request(:post, %r{https://discord\.com/api/v10/channels/.+/messages})
      .to_return(status: 200, body: { id: "fake_message_id" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:patch, %r{https://discord\.com/api/v10/channels/.+/messages/.+})
      .to_return(status: 200, body: { id: "fake_message_id" }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def build_interaction(discord_user_id, subcommand:, options: [])
    {
      "guild_id" => "svr_loot",
      "token"    => "test_token_loot",
      "member"   => { "user" => { "id" => discord_user_id } },
      "data"     => {
        "name"    => "loot",
        "options" => [
          { "type" => 1, "name" => subcommand.to_s, "options" => options }
        ]
      }
    }
  end

  describe "/loot list" do
    it "returns none_active when no open loot rolls exist" do
      result = described_class.handle(build_interaction("d_member_l", subcommand: :list))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.loot.none_active"))
    end

    it "lists open loot rolls" do
      loot_roll = create(:loot_roll, guild: guild, title: "Epic Sword", status: :open, creator: owner)
      result = described_class.handle(build_interaction("d_member_l", subcommand: :list))
      expect(result.dig(:data, :embeds, 0, :description)).to include("Epic Sword")
    end
  end

  describe "/loot view" do
    let(:loot_roll) { create(:loot_roll, guild: guild, status: :open, creator: owner) }

    it "returns embed for a valid loot roll" do
      result = described_class.handle(build_interaction("d_member_l", subcommand: :view,
                                                        options: [{ "name" => "loot_id", "value" => loot_roll.id }]))
      expect(result.dig(:data, :embeds, 0, :title)).to include(loot_roll.title)
    end

    it "returns not_found for an invalid loot roll" do
      result = described_class.handle(build_interaction("d_member_l", subcommand: :view,
                                                        options: [{ "name" => "loot_id", "value" => 9_999_999 }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.loot.not_found"))
    end
  end

  describe "/loot create" do
    let(:create_opts) do
      [{ "name" => "item_name", "value" => "Golden Ring" }, { "name" => "max", "value" => 100 }]
    end

    it "returns deferred for officer" do
      result = described_class.handle(build_interaction("d_officer_l", subcommand: :create, options: create_opts))
      expect(result[:type]).to eq(5)
    end

    it "returns officer_required error for plain member" do
      result = described_class.handle(build_interaction("d_member_l", subcommand: :create, options: create_opts))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
    end

    it "returns invalid_range when max <= min" do
      opts = [{ "name" => "item_name", "value" => "Ring" },
              { "name" => "min", "value" => 50 }, { "name" => "max", "value" => 10 }]
      result = described_class.handle(build_interaction("d_officer_l", subcommand: :create, options: opts))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.loot.invalid_range"))
    end

    it "returns no_channel when loot channel is not configured" do
      discord_setting.update!(loot_rolls_channel_id: nil)
      result = described_class.handle(build_interaction("d_officer_l", subcommand: :create, options: create_opts))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.loot.no_channel"))
    end
  end

  describe "/loot close" do
    let!(:open_loot) { create(:loot_roll, guild: guild, status: :open, creator: owner) }

    it "returns deferred for officer" do
      result = described_class.handle(build_interaction("d_officer_l", subcommand: :close,
                                                        options: [{ "name" => "loot_id", "value" => open_loot.id }]))
      expect(result[:type]).to eq(5)
    end

    it "returns already_closed if roll is closed" do
      open_loot.update!(status: :closed)
      result = described_class.handle(build_interaction("d_officer_l", subcommand: :close,
                                                        options: [{ "name" => "loot_id", "value" => open_loot.id }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.loot.already_closed"))
    end

    it "returns officer_required for plain member" do
      result = described_class.handle(build_interaction("d_member_l", subcommand: :close,
                                                        options: [{ "name" => "loot_id", "value" => open_loot.id }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
    end
  end

  # =========================================================================
  # process_* methods (called by DiscordCommandJob)
  # =========================================================================
  describe "#process_create" do
    let(:service) { described_class.new }

    before do
      service.instance_variable_set(:@guild, guild)
      service.instance_variable_set(:@user, officer_user)
      service.instance_variable_set(:@interaction_token, "tok_loot_create")
      service.instance_variable_set(:@guild_member, officer_member)

      stub_request(:post, %r{discord\.com/api/v10/webhooks/.+}).to_return(status: 200, body: "{}")
      allow_any_instance_of(DiscordLootRollService).to receive(:post_loot_roll)
    end

    it "creates a loot roll and sends a follow-up" do
      expect {
        service.send(:process_create, { item_name: "Blade of Fury", min_roll: 1, max_roll: 100 }.with_indifferent_access)
      }.to change(guild.loot_rolls, :count).by(1)
    end
  end

  describe "#process_close idempotency" do
    let(:service) { described_class.new }
    let!(:loot_roll) { create(:loot_roll, guild: guild, status: :open, creator: owner) }

    before do
      service.instance_variable_set(:@guild, guild)
      service.instance_variable_set(:@user, officer_user)
      service.instance_variable_set(:@interaction_token, "tok_loot_close")
      service.instance_variable_set(:@guild_member, officer_member)

      stub_request(:post, %r{discord\.com/api/v10/webhooks/.+}).to_return(status: 200, body: "{}")
      stub_request(:patch, %r{discord\.com/api/v10/channels/.+/messages/.+}).to_return(status: 200, body: "{}")
    end

    it "closes the loot roll on first call" do
      service.send(:process_close, { loot_id: loot_roll.id }.with_indifferent_access)
      expect(loot_roll.reload.status).to eq("closed")
    end

    it "sends follow-up without re-closing on idempotent retry" do
      loot_roll.update!(status: :closed)
      expect(loot_roll).not_to receive(:close_and_determine_winner!)
      service.send(:process_close, { loot_id: loot_roll.id }.with_indifferent_access)
    end
  end
end
