# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildActivityLogger, type: :service do
  let(:guild) { create(:guild) }
  let(:member_user) do
    u = create(:user)
    guild.guild_members.create!(user: u, role: :member, status: :active)
    u
  end
  let(:non_member_user) { create(:user) }

  describe ".log" do
    it "creates a log entry when the user is an active guild member" do
      expect {
        GuildActivityLogger.log(
          guild: guild,
          user: member_user,
          action_type: "document_created",
          description: "Created document \"Test\""
        )
      }.to change(GuildActivityLog, :count).by(1)

      log = GuildActivityLog.last
      expect(log.guild_id).to eq(guild.id)
      expect(log.user_id).to eq(member_user.id)
      expect(log.action_type).to eq("document_created")
      expect(log.description).to include("Test")
    end

    it "does not create a log entry when the user is not a guild member" do
      expect {
        GuildActivityLogger.log(
          guild: guild,
          user: non_member_user,
          action_type: "document_created",
          description: "Created document \"Test\""
        )
      }.not_to change(GuildActivityLog, :count)
    end

    it "creates a log entry when user is nil (e.g. system action)" do
      expect {
        GuildActivityLogger.log(
          guild: guild,
          user: nil,
          action_type: "system_event",
          description: "System did something"
        )
      }.to change(GuildActivityLog, :count).by(1)

      log = GuildActivityLog.last
      expect(log.user_id).to be_nil
    end

    it "does not create a log when guild is nil" do
      expect {
        GuildActivityLogger.log(
          guild: nil,
          user: member_user,
          action_type: "document_created",
          description: "Created document"
        )
      }.not_to change(GuildActivityLog, :count)
    end
  end
end
