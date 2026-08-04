# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordRoleRefreshJob, type: :job do
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let!(:discord_setting) do
    create(
      :guild_discord_setting,
      guild: guild,
      discord_guild_id: "123456789012345678",
      bot_token: "bot-token",
      connected_at: Time.current
    )
  end

  it "updates synced role names from live Discord roles" do
    sync = create(:discord_role_sync, guild: guild, role_id: "role-1", role_name: "Old Name")
    service = instance_double(DiscordService)
    allow(DiscordService).to receive(:new).and_return(service)
    allow(service).to receive(:get_guild_roles).and_return(
      [
        { "id" => "role-1", "name" => "New Name" }
      ]
    )

    described_class.new.perform

    expect(sync.reload.role_name).to eq("New Name")
  end

  it "removes sync rows for roles deleted from Discord" do
    sync = create(:discord_role_sync, guild: guild, role_id: "deleted-role", role_name: "Deleted")
    service = instance_double(DiscordService)
    allow(DiscordService).to receive(:new).and_return(service)
    allow(service).to receive(:get_guild_roles).and_return([])

    expect do
      described_class.new.perform
    end.to change { DiscordRoleSync.exists?(sync.id) }.from(true).to(false)
  end
end
