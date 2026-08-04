# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceDiscordBroadcastService, type: :service do
  let(:owner) { create(:user) }
  let(:other_owner) { create(:user) }
  let(:leader_guild) { create(:guild, owner: owner) }
  let(:invited_guild) { create(:guild, owner: other_owner) }

  let!(:invited_discord_setting) do
    create(:guild_discord_setting,
           guild: invited_guild,
           discord_guild_id: "123456789012345678",
           bot_token: "test_bot_token",
           connected_at: Time.current,
           alliance_invites_channel_id: "222")
  end

  describe ".notify_invite_created" do
    let(:alliance) { create(:alliance, leader_guild: leader_guild, leader_user: owner) }
    let(:invite) do
      create(:alliance_invite, alliance: alliance, guild: invited_guild, invited_by_user: owner)
    end

    it "posts using the invited guild bot token" do
      svc = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).with(bot_token: invited_discord_setting.bot_token).and_return(svc)
      allow(svc).to receive(:send_message).and_return({ "id" => "m1" })

      described_class.notify_invite_created(invite)

      expect(svc).to have_received(:send_message).with("222", "", hash_including(embed: kind_of(Hash)))
    end

    it "skips when no channel configured" do
      invited_discord_setting.update_columns(alliance_invites_channel_id: nil, alliance_events_channel_id: nil,
                                             alliance_polls_channel_id: nil, alliance_loot_rolls_channel_id: nil)
      invite
      expect(DiscordService).not_to receive(:new)

      described_class.notify_invite_created(invite)
    end

    it "falls back to global bot token when guild token is blank" do
      invited_discord_setting.update!(bot_token: nil)
      svc = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).with(bot_token: "env_fallback_token").and_return(svc)
      allow(svc).to receive(:send_message).and_return({ "id" => "m2" })
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DISCORD_BOT_TOKEN").and_return("env_fallback_token")

      described_class.notify_invite_created(invite)

      expect(svc).to have_received(:send_message).with("222", "", hash_including(embed: kind_of(Hash)))
    end
  end

  describe ".notify_join_request_created" do
    let(:requesting_owner) { create(:user) }
    let(:alliance) { create(:alliance, leader_guild: leader_guild, leader_user: owner) }
    let(:requesting_guild) { create(:guild, owner: requesting_owner) }
    let(:join_request) do
      create(:alliance_join_request,
             alliance: alliance,
             requesting_guild: requesting_guild,
             requested_by_user: requesting_owner)
    end

    let!(:leader_discord_setting) do
      create(:guild_discord_setting,
             guild: leader_guild,
             discord_guild_id: "111111111111111111",
             bot_token: "tok_leader_jr",
             connected_at: Time.current,
             alliance_invites_channel_id: "555")
    end

    before do
      AllianceGuild.create!(alliance: alliance, guild: leader_guild, status: :active, joined_at: Time.current, invited_by_user: owner)
    end

    it "interpolates guild_name and alliance_name in the embed (no I18n missing keys)" do
      svc = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).with(bot_token: "tok_leader_jr").and_return(svc)
      captured = nil
      allow(svc).to receive(:send_message) do |_ch, _content, kwargs|
        captured = kwargs[:embed]
        { "id" => "jr1" }
      end

      described_class.notify_join_request_created(join_request)

      expect(captured[:description]).to include(requesting_guild.name)
      expect(captured[:description]).to include(alliance.name)
    end
  end

  describe ".broadcast_alliance_event_created" do
    let(:alliance) { create(:alliance, leader_guild: leader_guild, leader_user: owner) }
    let(:event) { create(:alliance_event, alliance: alliance, created_by: owner, title: "Raid", description: "Hi") }

    let!(:leader_discord_setting) do
      create(:guild_discord_setting,
             guild: leader_guild,
             discord_guild_id: "987654321098765432",
             bot_token: "tok_leader",
             connected_at: Time.current,
             alliance_events_channel_id: "444")
    end

    before do
      AllianceGuild.create!(alliance: alliance, guild: leader_guild, status: :active, joined_at: Time.current, invited_by_user: owner)
    end

    it "posts to configured alliance event channels" do
      gs = leader_guild.reload.guild_discord_setting
      svc = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).with(bot_token: gs.bot_token).and_return(svc)
      captured_embed = nil
      allow(svc).to receive(:send_message) do |_ch, _content, kwargs|
        captured_embed = kwargs[:embed]
        { "id" => "x" }
      end
      allow(svc).to receive(:create_scheduled_event!).and_return("discord_sched_1")

      described_class.broadcast_alliance_event_created(alliance, event)

      expect(captured_embed.dig(:footer, :text)).to include(gs.discord_guild_name)

      expect(svc).to have_received(:send_message).with(
        "444",
        a_string_including("@everyone"),
        hash_including(
          allowed_mentions: AllianceDiscordBroadcastService::EVERYONE_ALLOWED_MENTIONS,
          embed: kind_of(Hash),
          components: array_including(
            hash_including(
              type: 1,
              components: array_including(
                hash_including(custom_id: "alliance_event_signup_#{event.id}_dps"),
                hash_including(custom_id: "alliance_event_signup_#{event.id}_tank"),
                hash_including(custom_id: "alliance_event_signup_#{event.id}_healer"),
                hash_including(custom_id: "alliance_event_signup_#{event.id}_ranged")
              )
            )
          )
        )
      )
      expect(svc).to have_received(:create_scheduled_event!).with(
        hash_including(
          guild: leader_guild,
          channel_id: "444",
          name: "Raid",
          start_time: event.scheduled_at,
          duration_minutes: event.duration
        )
      )
      link = event.alliance_event_discord_messages.find_by(guild: leader_guild)
      expect(link).to be_present
      expect(link.discord_scheduled_event_id).to eq("discord_sched_1")
    end

    it "posts even when connected_at is missing but channel and token exist" do
      gs = leader_guild.reload.guild_discord_setting
      gs.update_columns(connected_at: nil)

      svc = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).with(bot_token: gs.bot_token).and_return(svc)
      allow(svc).to receive(:send_message).and_return({ "id" => "x2" })
      allow(svc).to receive(:create_scheduled_event!).and_return("discord_sched_2")

      described_class.broadcast_alliance_event_created(alliance, event)

      expect(svc).to have_received(:send_message).with(
        "444",
        a_string_including("@everyone"),
        hash_including(
          allowed_mentions: AllianceDiscordBroadcastService::EVERYONE_ALLOWED_MENTIONS,
          embed: kind_of(Hash),
          components: kind_of(Array)
        )
      )
    end
  end

  describe ".broadcast_alliance_event_updated / .broadcast_alliance_event_deleted" do
    let(:alliance) { create(:alliance, leader_guild: leader_guild, leader_user: owner) }
    let(:event) { create(:alliance_event, alliance: alliance, created_by: owner, title: "Raid", description: "Hi") }
    let!(:leader_discord_setting) do
      create(:guild_discord_setting,
             guild: leader_guild,
             discord_guild_id: "777777777777777777",
             bot_token: "tok_update",
             connected_at: Time.current,
             alliance_events_channel_id: "999")
    end
    let!(:message_link) do
      create(:alliance_event_discord_message,
             alliance_event: event,
             guild: leader_guild,
             channel_id: "999",
             discord_message_id: "111111111111111111",
             discord_scheduled_event_id: "sched_to_patch",
             posted_at: Time.current)
    end

    it "updates posted alliance event messages" do
      svc = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).with(bot_token: "tok_update").and_return(svc)
      allow(svc).to receive(:update_message).and_return({})
      allow(svc).to receive(:patch_scheduled_event!).and_return(true)

      described_class.broadcast_alliance_event_updated(event)

      expect(svc).to have_received(:update_message).with(
        "999",
        "111111111111111111",
        a_string_including("@everyone"),
        hash_including(
          allowed_mentions: AllianceDiscordBroadcastService::EVERYONE_ALLOWED_MENTIONS,
          embed: kind_of(Hash),
          components: kind_of(Array)
        )
      )
      expect(svc).to have_received(:patch_scheduled_event!).with(
        hash_including(
          guild: leader_guild,
          scheduled_event_id: "sched_to_patch",
          name: "Raid",
          start_time: event.scheduled_at
        )
      )
    end

    it "deletes posted alliance event messages and clears links" do
      svc = instance_double(DiscordService)
      allow(DiscordService).to receive(:new).with(bot_token: "tok_update").and_return(svc)
      allow(svc).to receive(:delete_scheduled_event!).and_return(true)
      allow(svc).to receive(:delete_message).and_return(true)

      described_class.broadcast_alliance_event_deleted(event)

      expect(svc).to have_received(:delete_scheduled_event!).with(
        hash_including(guild: leader_guild, scheduled_event_id: "sched_to_patch")
      )
      expect(svc).to have_received(:delete_message).with("999", "111111111111111111")
      expect(event.alliance_event_discord_messages.reload).to be_empty
    end
  end
end
