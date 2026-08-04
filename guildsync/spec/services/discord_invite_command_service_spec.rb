# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordInviteCommandService, type: :service do
  include_context "Discord API stubs"

  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner) }
  let!(:discord_setting) { create(:guild_discord_setting, guild: guild, discord_guild_id: "svr_invite") }
  let!(:owner_conn) { create(:user_discord_connection, user: owner, discord_user_id: "d_owner_i") }
  let(:member_user)  { create(:user) }
  let!(:member_conn) { create(:user_discord_connection, user: member_user, discord_user_id: "d_member_i") }
  let!(:member_record) { guild.guild_members.create!(user: member_user, role: :member, status: :active) }

  before do
    stub_request(:post, %r{https://discord\.com/api/v10/users/@me/channels})
      .to_return(status: 200, body: { id: "dm_channel_id" }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:post, %r{https://discord\.com/api/v10/channels/.+/messages})
      .to_return(status: 200, body: { id: "dm_msg_id" }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def build_interaction(invoker_id, target_id: "d_target_outsider", message: nil)
    options = [{ "name" => "user", "value" => target_id }]
    options << { "name" => "message", "value" => message } if message
    {
      "guild_id" => "svr_invite",
      "token"    => "token_invite",
      "member"   => { "user" => { "id" => invoker_id } },
      "data"     => { "name" => "invite", "options" => options }
    }
  end

  it "returns deferred response when inviting a valid outsider" do
    create(:user_discord_connection, discord_user_id: "d_target_outsider")
    result = described_class.handle(build_interaction("d_member_i"))
    expect(result[:type]).to eq(5)
  end

  it "returns self_invite error when user invites themselves" do
    result = described_class.handle(build_interaction("d_member_i", target_id: "d_member_i"))
    expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.invite.self_invite"))
  end

  it "returns already_member error when target is already in the guild" do
    existing_user = create(:user)
    create(:user_discord_connection, user: existing_user, discord_user_id: "d_existing")
    guild.guild_members.create!(user: existing_user, role: :member, status: :active)

    result = described_class.handle(build_interaction("d_member_i", target_id: "d_existing"))
    expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.invite.already_member"))
  end

  it "returns user_not_linked error when target has no GuildSync account" do
    result = described_class.handle(build_interaction("d_member_i", target_id: "unlinked_id"))
    expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.errors.user_not_linked"))
  end

  it "returns no_user error when user option is blank" do
    interaction = {
      "guild_id" => "svr_invite",
      "token"    => "token_invite",
      "member"   => { "user" => { "id" => "d_member_i" } },
      "data"     => { "name" => "invite", "options" => [] }
    }
    result = described_class.handle(interaction)
    expect(result.dig(:data, :content)).to include(I18n.t("discord.commands.invite.no_user"))
  end

  # =========================================================================
  # process_invite (called by DiscordCommandJob)
  # =========================================================================
  describe "#process_invite" do
    let(:service) { described_class.new }
    let(:target_user) { create(:user) }
    let!(:target_conn) { create(:user_discord_connection, user: target_user, discord_user_id: "d_target_proc") }

    before do
      service.instance_variable_set(:@guild, guild)
      service.instance_variable_set(:@user, member_user)
      service.instance_variable_set(:@interaction_token, "tok_invite_proc")
      service.instance_variable_set(:@guild_member, member_record)

      stub_request(:post, %r{discord\.com/api/v10/webhooks/.+}).to_return(status: 200, body: "{}")
      allow_any_instance_of(DiscordService).to receive(:send_dm)

    end

    it "does not create a link when the guild is at active invite link capacity" do
      Guild::MAX_ACTIVE_INVITE_LINKS.times do
        guild.guild_invite_links.create!(created_by: member_user, expires_at: 8.days.from_now)
      end
      allow(service).to receive(:send_followup)
      expect {
        service.send(:process_invite, {
          target_discord_id: "d_target_proc",
          personal_message: nil
        }.with_indifferent_access)
      }.not_to change { guild.reload.guild_invite_links.count }
      expect(service).to have_received(:send_followup).with(
        "tok_invite_proc",
        I18n.t("join.invite_links_limit", count: Guild::MAX_ACTIVE_INVITE_LINKS),
        ephemeral: true
      )
    end

    it "creates an invite link with expiry" do
      expect {
        service.send(:process_invite, {
          target_discord_id: "d_target_proc",
          personal_message: "Join us!"
        }.with_indifferent_access)
      }.to change(guild.guild_invite_links, :count).by(1)

      link = guild.guild_invite_links.last
      expect(link.expires_at).to be_present
      expect(link.expires_at).to be > 6.days.from_now
    end

    it "sends a DM to the target user" do
      expect_any_instance_of(DiscordService).to receive(:send_dm).with("d_target_proc", anything)

      service.send(:process_invite, {
        target_discord_id: "d_target_proc",
        personal_message: nil
      }.with_indifferent_access)
    end

    it "handles DM-disabled (403) gracefully" do
      response = double("Response", code: 403, body: "Forbidden", to_s: "403 Forbidden")
      exception = RestClient::Forbidden.new(response)
      allow_any_instance_of(DiscordService).to receive(:send_dm).and_raise(exception)

      expect {
        service.send(:process_invite, {
          target_discord_id: "d_target_proc",
          personal_message: nil
        }.with_indifferent_access)
      }.not_to raise_error
    end
  end
end
