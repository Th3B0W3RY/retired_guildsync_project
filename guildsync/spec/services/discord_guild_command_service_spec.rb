# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordGuildCommandService, type: :service do
  include_context "Discord API stubs"

  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner) }
  let!(:ds) do
    create(:guild_discord_setting, guild: guild, discord_guild_id: "svr_guild",
           events_channel_id: "chan_ev", polls_channel_id: "chan_po")
  end
  let!(:owner_conn) { create(:user_discord_connection, user: owner, discord_user_id: "d_own_g") }
  let(:officer) { create(:user) }
  let!(:off_conn)   { create(:user_discord_connection, user: officer, discord_user_id: "d_off_g") }
  let!(:off_member) { guild.guild_members.create!(user: officer, role: :admin, status: :active) }
  let(:regular) { create(:user) }
  let!(:reg_conn)   { create(:user_discord_connection, user: regular, discord_user_id: "d_reg_g") }
  let!(:reg_member) { guild.guild_members.create!(user: regular, role: :member, status: :active) }

  def interaction(invoker_id, subcommand:)
    {
      "guild_id" => "svr_guild",
      "token"    => "tok_guild",
      "member"   => { "user" => { "id" => invoker_id } },
      "data"     => {
        "name"    => "guild",
        "options" => [{ "type" => 1, "name" => subcommand.to_s, "options" => [] }]
      }
    }
  end

  describe "/guild info" do
    it "returns an embed with guild name in title" do
      result = described_class.handle(interaction("d_reg_g", subcommand: :info))
      expect(result.dig(:data, :embeds, 0, :title)).to include(guild.name)
    end
  end

  describe "/guild settings" do
    it "returns owner_required for a regular member" do
      result = described_class.handle(interaction("d_reg_g", subcommand: :settings))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.owner_required"))
    end

    it "returns settings embed for the guild owner" do
      result = described_class.handle(interaction("d_own_g", subcommand: :settings))
      expect(result.dig(:data, :embeds, 0, :title)).to include(guild.name)
    end
  end

  describe "/guild channels" do
    it "returns officer_required for a regular member" do
      result = described_class.handle(interaction("d_reg_g", subcommand: :channels))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
    end

    it "returns channels embed for an officer" do
      result = described_class.handle(interaction("d_off_g", subcommand: :channels))
      expect(result.dig(:data, :embeds, 0, :title)).to include(guild.name)
    end
  end
end
