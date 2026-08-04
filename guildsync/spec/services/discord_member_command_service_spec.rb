# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordMemberCommandService, type: :service do
  include_context "Discord API stubs"

  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner) }
  let!(:ds) { create(:guild_discord_setting, guild: guild, discord_guild_id: "svr_member") }
  let!(:owner_conn) { create(:user_discord_connection, user: owner, discord_user_id: "d_own_m") }
  let(:officer) { create(:user) }
  let!(:off_conn)   { create(:user_discord_connection, user: officer, discord_user_id: "d_off_m") }
  let!(:off_member) { guild.guild_members.create!(user: officer, role: :moderator, status: :active) }
  let(:regular) { create(:user) }
  let!(:reg_conn)   { create(:user_discord_connection, user: regular, discord_user_id: "d_reg_m") }
  let!(:reg_member) { guild.guild_members.create!(user: regular, role: :member, status: :active) }

  def interaction(invoker_id, subcommand:, options: [])
    {
      "guild_id" => "svr_member",
      "token"    => "token_member",
      "member"   => { "user" => { "id" => invoker_id } },
      "data"     => {
        "name"    => "member",
        "options" => [{ "type" => 1, "name" => subcommand.to_s, "options" => options }]
      }
    }
  end

  describe "/member list" do
    it "returns embed with member names" do
      result = described_class.handle(interaction("d_reg_m", subcommand: :list))
      expect(result.dig(:data, :embeds, 0, :description)).to include(owner.username).or include(regular.username)
    end
  end

  describe "/member info" do
    it "returns not_found for unknown discord user" do
      result = described_class.handle(interaction("d_reg_m", subcommand: :info,
                                                  options: [{ "name" => "user", "value" => "unknown_id" }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.member.not_found"))
    end

    it "returns embed for a known member" do
      result = described_class.handle(interaction("d_reg_m", subcommand: :info,
                                                  options: [{ "name" => "user", "value" => "d_reg_m" }]))
      expect(result.dig(:data, :embeds, 0, :title)).to include(regular.username)
    end
  end

  describe "/member kick" do
    it "returns officer_required for a regular member" do
      result = described_class.handle(interaction("d_reg_m", subcommand: :kick,
                                                  options: [{ "name" => "user", "value" => "d_off_m" }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
    end

    it "cannot kick the guild owner" do
      result = described_class.handle(interaction("d_off_m", subcommand: :kick,
                                                  options: [{ "name" => "user", "value" => "d_own_m" }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.member.cannot_kick_owner"))
    end

    it "successfully kicks a regular member (returns kicked message)" do
      result = described_class.handle(interaction("d_off_m", subcommand: :kick,
                                                  options: [{ "name" => "user", "value" => "d_reg_m" }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.member.kicked",
                                                             username: regular.display_name.presence || regular.username))
    end
  end

  describe "/member role" do
    it "returns officer_required for a regular member" do
      result = described_class.handle(interaction("d_reg_m", subcommand: :role,
                                                  options: [{ "name" => "user", "value" => "d_off_m" },
                                                            { "name" => "role", "value" => "member" }]))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.officer_required"))
    end

    it "updates the role for a valid member" do
      result = described_class.handle(interaction("d_off_m", subcommand: :role,
                                                  options: [{ "name" => "user", "value" => "d_reg_m" },
                                                            { "name" => "role", "value" => "moderator" }]))
      expect(result.dig(:data, :content)).to include("Moderator")
      expect(reg_member.reload.role).to eq("moderator")
    end
  end
end
