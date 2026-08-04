# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordReactRolesService, type: :service do
  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner, discord_id: "9876543210") }
  let!(:synced_role) { create(:discord_role_sync, guild: guild, role_id: "11122233344455", role_name: "Raiders") }

  let!(:rr1) do
    create(:react_role, guild: guild, position: 1,
           role_id: synced_role.role_id, role_name: synced_role.role_name,
           emoji_name: "🔥", is_custom_emoji: false,
           channel_id: "555666777888")
  end

  subject(:service) { described_class.new(guild) }

  # Shared Discord API stubs
  before do
    stub_request(:post, /discord\.com.*\/messages/)
      .to_return(status: 200, body: { id: "123456789" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:patch, /discord\.com.*\/messages\//)
      .to_return(status: 200, body: { id: "123456789" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:put, /discord\.com.*\/reactions\//)
      .to_return(status: 204, body: "")
    stub_request(:delete, /discord\.com.*\/messages\//)
      .to_return(status: 204, body: "")
    stub_request(:put, /discord\.com.*\/roles\//)
      .to_return(status: 204, body: "")
    stub_request(:delete, /discord\.com.*\/roles\//)
      .to_return(status: 204, body: "")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("test_bot_token")
  end

  # ──────────────────────────────────────────────────────────────────────────
  # deploy_embed
  # ──────────────────────────────────────────────────────────────────────────

  describe "#deploy_embed" do
    context "when no react roles are configured" do
      before { guild.react_roles.destroy_all }

      it "raises an error" do
        expect { service.deploy_embed }.to raise_error(/No react roles/)
      end
    end

    context "when channel_id is absent" do
      before { rr1.update!(channel_id: nil) }

      it "raises an error" do
        expect { service.deploy_embed }.to raise_error(/channel not set/)
      end
    end

    context "with a configured react role and no prior message" do
      it "POSTs a new message to Discord" do
        service.deploy_embed

        expect(WebMock).to have_requested(:post, /channels\/#{rr1.channel_id}\/messages/)
      end

      it "stores the returned message_id on all ReactRole rows" do
        service.deploy_embed

        expect(rr1.reload.message_id).to eq("123456789")
      end

      it "adds a bot reaction for each react role" do
        service.deploy_embed

        expect(WebMock).to have_requested(:put, /reactions/)
      end
    end

    context "when a message already exists" do
      before { rr1.update!(message_id: "999000111") }

      it "PATCHes the existing message instead of posting" do
        service.deploy_embed

        expect(WebMock).to have_requested(:patch, /messages\/999000111/)
        expect(WebMock).not_to have_requested(:post, /\/messages$/)
      end

      context "when Discord returns 404 (message was deleted)" do
        before do
          stub_request(:patch, /discord\.com.*\/messages\/999000111/)
            .to_return(status: 404, body: { code: 10008, message: "Unknown Message" }.to_json,
                       headers: { "Content-Type" => "application/json" })
        end

        it "falls back to posting a new message" do
          service.deploy_embed

          expect(WebMock).to have_requested(:post, /\/messages/)
        end
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # handle_reaction_add
  # ──────────────────────────────────────────────────────────────────────────

  describe "#handle_reaction_add" do
    before { rr1.update!(message_id: "123456789") }

    it "calls the Discord API to add the role to the user" do
      service.handle_reaction_add("USER111", "123456789", "🔥", nil)

      expect(WebMock).to have_requested(:put,
        /guilds\/#{guild.discord_id}\/members\/USER111\/roles\/#{rr1.role_id}/)
    end

    it "does nothing if the emoji doesn't match any react role" do
      service.handle_reaction_add("USER111", "123456789", "❄️", nil)

      expect(WebMock).not_to have_requested(:put, /roles/)
    end

    it "does nothing if the message_id doesn't match any react role" do
      service.handle_reaction_add("USER111", "BADMSG", "🔥", nil)

      expect(WebMock).not_to have_requested(:put, /roles/)
    end

    it "falls back to guild_discord_setting.discord_guild_id when guild.discord_id is blank" do
      create(:guild_discord_setting, guild: guild, discord_guild_id: "FALLBACK_GUILD_ID")
      guild.update!(discord_id: nil)

      service.handle_reaction_add("USER111", "123456789", "🔥", nil)

      expect(WebMock).to have_requested(:put,
        /guilds\/FALLBACK_GUILD_ID\/members\/USER111\/roles\/#{rr1.role_id}/)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # handle_reaction_remove
  # ──────────────────────────────────────────────────────────────────────────

  describe "#handle_reaction_remove" do
    before { rr1.update!(message_id: "123456789") }

    it "calls the Discord API to remove the role from the user" do
      service.handle_reaction_remove("USER111", "123456789", "🔥", nil)

      expect(WebMock).to have_requested(:delete,
        /guilds\/#{guild.discord_id}\/members\/USER111\/roles\/#{rr1.role_id}/)
    end

    it "does nothing if the emoji doesn't match" do
      service.handle_reaction_remove("USER111", "123456789", "❄️", nil)

      expect(WebMock).not_to have_requested(:delete, /roles/)
    end

    it "falls back to guild_discord_setting.discord_guild_id when guild.discord_id is blank" do
      create(:guild_discord_setting, guild: guild, discord_guild_id: "FALLBACK_GUILD_ID")
      guild.update!(discord_id: nil)

      service.handle_reaction_remove("USER111", "123456789", "🔥", nil)

      expect(WebMock).to have_requested(:delete,
        /guilds\/FALLBACK_GUILD_ID\/members\/USER111\/roles\/#{rr1.role_id}/)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # handle_reaction_add with custom emoji
  # ──────────────────────────────────────────────────────────────────────────

  describe "custom emoji matching" do
    let!(:rr_custom) do
      create(:react_role, :custom_emoji, guild: guild, position: 2,
             role_id: synced_role.role_id, role_name: synced_role.role_name,
             channel_id: "555666777888", message_id: "999888777")
    end

    it "matches by emoji_id for custom emojis" do
      service.handle_reaction_add("USER222", "999888777", "LUL", "41771983429993937")

      expect(WebMock).to have_requested(:put,
        /guilds\/#{guild.discord_id}\/members\/USER222\/roles\/#{rr_custom.role_id}/)
    end

    it "does not match when emoji_id differs" do
      service.handle_reaction_add("USER222", "999888777", "LUL", "WRONG_ID")

      expect(WebMock).not_to have_requested(:put, /roles/)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # remove_embed
  # ──────────────────────────────────────────────────────────────────────────

  describe "#remove_embed" do
    before { rr1.update!(message_id: "123456789", channel_id: "555666777888") }

    it "sends a DELETE request to Discord for the embed message" do
      service.remove_embed

      expect(WebMock).to have_requested(:delete,
        /channels\/555666777888\/messages\/123456789/)
    end

    it "clears message_id and channel_id from all ReactRole rows" do
      service.remove_embed

      expect(rr1.reload.message_id).to be_nil
      expect(rr1.reload.channel_id).to be_nil
    end

    it "is a no-op when no message_id exists" do
      rr1.update!(message_id: nil)

      expect { service.remove_embed }.not_to raise_error
      expect(WebMock).not_to have_requested(:delete, /messages/)
    end
  end
end
