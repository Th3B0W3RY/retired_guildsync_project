# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guilds::MemberLeaderboardScores do
  let(:user) { create(:user, skip_free_plan_subscription: true) }
  let!(:pricing_plan) { create(:pricing_plan, max_guilds: 10) }
  let!(:subscription) { create(:subscription, user: user, pricing_plan: pricing_plan) }
  let(:guild) { create(:guild, owner: user) }
  let!(:discord_setting) { create(:guild_discord_setting, guild: guild, discord_guild_name: "GS Test") }

  describe ".call" do
    it "returns empty array when guild ids empty" do
      expect(described_class.call(user_guild_ids: [])).to eq([])
    end

    it "applies heavy weight to on-time event participations" do
      e1 = create(:event, guild: guild, status: :in_progress)
      e2 = create(:event, guild: guild, status: :completed)
      [ e1, e2 ].each do |event|
        create(:discord_event_participation,
               event: event,
               discord_user_id: "same_discord",
               discord_username: "SameUser#0001",
               on_time: true)
      end

      rows = described_class.call(user_guild_ids: [ guild.id ])
      expect(rows.size).to eq(1)
      expect(rows.first[:score]).to eq(20)
      expect(rows.first[:discord_username]).to eq("SameUser#0001")
    end

    it "combines events, poll votes, and closed loot roll entries" do
      event = create(:event, guild: guild, status: :completed)
      create(:discord_event_participation,
             event: event,
             discord_user_id: "combo_id",
             discord_username: "Combo#99",
             on_time: true)

      poll = create(:poll, guild: guild, creator: user)
      PollVote.create!(poll: poll, choice: :yes, discord_user_id: "combo_id", discord_username: "Combo#99")

      loot = create(:loot_roll, guild: guild, creator: user, status: :open)
      create(:loot_roll_entry, loot_roll: loot, discord_user_id: "combo_id", display_name: "Combo", roll_value: 50)
      loot.update!(status: :closed)

      rows = described_class.call(user_guild_ids: [ guild.id ])
      expect(rows.size).to eq(1)
      # 10 event + 10 poll + 1 loot
      expect(rows.first[:score]).to eq(21)
    end

    it "does not count loot entries on open rolls" do
      loot = create(:loot_roll, guild: guild, creator: user, status: :open)
      create(:loot_roll_entry, loot_roll: loot, discord_user_id: "only_loot", display_name: "L", roll_value: 10)

      rows = described_class.call(user_guild_ids: [ guild.id ])
      expect(rows).to eq([])
    end

    it "does not count scheduled events" do
      event = create(:event, guild: guild, status: :scheduled)
      create(:discord_event_participation,
             event: event,
             discord_user_id: "late",
             discord_username: "Late#1",
             on_time: true)

      expect(described_class.call(user_guild_ids: [ guild.id ])).to eq([])
    end
  end
end
