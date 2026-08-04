# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildDiscordSetting, type: :model do
  let(:guild) { create(:guild) }
  subject(:setting) { build(:guild_discord_setting, guild: guild) }

  # ---------------------------------------------------------------------------
  describe "validations" do
    it "is valid with a blank default_timezone" do
      setting.default_timezone = nil
      expect(setting).to be_valid
    end

    it "is valid with a recognised Rails timezone name" do
      setting.default_timezone = "Pacific Time (US & Canada)"
      expect(setting).to be_valid
    end

    it "is invalid with an unrecognised timezone string" do
      setting.default_timezone = "Not A Real Timezone"
      expect(setting).not_to be_valid
      expect(setting.errors[:default_timezone]).to be_present
    end

    it "is invalid with an arbitrary string" do
      setting.default_timezone = "UTC+5:30"
      expect(setting).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  describe "#timezone" do
    it "returns the configured default_timezone when present" do
      setting.default_timezone = "Central Time (US & Canada)"
      expect(setting.timezone).to eq("Central Time (US & Canada)")
    end

    it "falls back to Eastern Time when default_timezone is nil" do
      setting.default_timezone = nil
      expect(setting.timezone).to eq("Eastern Time (US & Canada)")
    end

    it "falls back to Eastern Time when default_timezone is blank" do
      setting.default_timezone = ""
      expect(setting.timezone).to eq("Eastern Time (US & Canada)")
    end
  end

  # ---------------------------------------------------------------------------
  describe "#connected?" do
    it "returns true when discord_guild_id and connected_at are present" do
      expect(setting.connected?).to be true
    end

    it "returns false when connected_at is missing" do
      setting.connected_at = nil
      expect(setting.connected?).to be false
    end
  end

  # ---------------------------------------------------------------------------
  describe "channel configuration helpers" do
    it "#events_channel_configured? returns false by default" do
      setting.events_channel_id = nil
      expect(setting.events_channel_configured?).to be false
    end

    it "#events_channel_configured? returns true when set" do
      setting.events_channel_id = "123"
      expect(setting.events_channel_configured?).to be true
    end

    it "#polls_channel_configured? returns false by default" do
      setting.polls_channel_id = nil
      expect(setting.polls_channel_configured?).to be false
    end

    it "#gear_channel_configured? returns false by default" do
      setting.gear_channel_id = nil
      expect(setting.gear_channel_configured?).to be false
    end

    it "#loot_rolls_channel_configured? returns false by default" do
      setting.loot_rolls_channel_id = nil
      expect(setting.loot_rolls_channel_configured?).to be false
    end
  end
end
