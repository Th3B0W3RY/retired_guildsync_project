# frozen_string_literal: true

require "rails_helper"

# Combined spec for the four Phase 3 read-only/utility commands:
# /docs, /leaderboard, /activity, /profile, /help
RSpec.describe "Phase 3 Discord Commands", type: :service do
  include_context "Discord API stubs"

  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner) }
  let!(:ds) { create(:guild_discord_setting, guild: guild, discord_guild_id: "svr_p3") }
  let!(:owner_conn) { create(:user_discord_connection, user: owner, discord_user_id: "d_own_p3") }
  let(:member_user) { create(:user) }
  let!(:member_conn) { create(:user_discord_connection, user: member_user, discord_user_id: "d_mem_p3") }
  let!(:member_record) { guild.guild_members.create!(user: member_user, role: :member, status: :active) }

  def interaction(invoker_id, command:, subcommand: nil, options: [], guild_id: "svr_p3")
    sc_options = subcommand ? [{ "type" => 1, "name" => subcommand.to_s, "options" => options }] : options
    {
      "guild_id" => guild_id,
      "token"    => "tok_p3",
      "member"   => { "user" => { "id" => invoker_id } },
      "data"     => { "name" => command.to_s, "options" => sc_options }
    }
  end

  # =========================================================================
  describe DiscordDocsCommandService do
    describe "/docs list" do
      it "returns none message when no documents exist" do
        result = described_class.handle(interaction("d_mem_p3", command: :docs, subcommand: :list))
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.docs.none"))
      end

      it "lists public documents" do
        doc = create(:guild_document, guild: guild, user: owner, visibility: :public_doc, title: "Strategy Guide")
        result = described_class.handle(interaction("d_mem_p3", command: :docs, subcommand: :list))
        expect(result.dig(:data, :embeds, 0, :description)).to include("Strategy Guide")
      end

      it "does not list private documents" do
        create(:guild_document, guild: guild, user: owner, visibility: :private_doc, title: "Secret Doc")
        result = described_class.handle(interaction("d_mem_p3", command: :docs, subcommand: :list))
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.docs.none"))
      end
    end

    describe "/docs view" do
      it "returns not_found for invalid doc_id" do
        result = described_class.handle(interaction("d_mem_p3", command: :docs, subcommand: :view,
                                                    options: [{ "name" => "doc_id", "value" => 9_999_999 }]))
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.docs.not_found"))
      end

      it "returns doc preview for a valid public document" do
        doc = create(:guild_document, guild: guild, user: owner, visibility: :public_doc, title: "Rulebook")
        result = described_class.handle(interaction("d_mem_p3", command: :docs, subcommand: :view,
                                                    options: [{ "name" => "doc_id", "value" => doc.id }]))
        expect(result.dig(:data, :embeds, 0, :title)).to eq("Rulebook")
      end
    end

    describe "/docs search" do
      it "returns search_none when no documents match" do
        result = described_class.handle(interaction("d_mem_p3", command: :docs, subcommand: :search,
                                                    options: [{ "name" => "query", "value" => "xyzxyz" }]))
        expect(result.dig(:data, :content)).to include("xyzxyz")
      end
    end
  end

  # =========================================================================
  describe DiscordLeaderboardCommandService do
    it "returns none message when there are no signup records" do
      result = described_class.handle(interaction("d_mem_p3", command: :leaderboard))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.leaderboard.none"))
    end
  end

  # =========================================================================
  describe DiscordActivityCommandService do
    it "returns none message when there are no activity logs" do
      result = described_class.handle(interaction("d_mem_p3", command: :activity))
      expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.activity.none"))
    end

    it "returns recent activity when logs exist" do
      guild.guild_activity_logs.create!(action_type: "test", description: "Did something cool", user: owner)
      result = described_class.handle(interaction("d_mem_p3", command: :activity))
      expect(result.dig(:data, :embeds, 0, :description)).to include("Did something cool")
    end
  end

  # =========================================================================
  describe DiscordProfileCommandService do
    describe "/profile me" do
      it "returns the invoking member's profile embed" do
        result = described_class.handle(interaction("d_mem_p3", command: :profile, subcommand: :me))
        expect(result.dig(:data, :embeds, 0, :title)).to include(member_user.username)
      end
    end

    describe "/profile view" do
      it "returns not_found for unknown discord user" do
        result = described_class.handle(interaction("d_mem_p3", command: :profile, subcommand: :view,
                                                    options: [{ "name" => "user", "value" => "unknown_user_id" }]))
        expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.profile.not_found"))
      end

      it "returns the target member's profile embed" do
        result = described_class.handle(interaction("d_mem_p3", command: :profile, subcommand: :view,
                                                    options: [{ "name" => "user", "value" => "d_mem_p3" }]))
        expect(result.dig(:data, :embeds, 0, :title)).to include(member_user.username)
      end
    end
  end

  # =========================================================================
  describe DiscordHelpCommandService do
    it "returns an ephemeral embed with help content" do
      result = described_class.handle(interaction("d_mem_p3", command: :help))
      expect(result[:type]).to eq(4)
      expect(result.dig(:data, :flags)).to eq(64)
      expect(result.dig(:data, :embeds, 0, :title)).to eq(I18n.t("discord.commands.help.title"))
    end
  end
end
