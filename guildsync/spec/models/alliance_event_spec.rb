# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllianceEvent, type: :model do
  describe ".event_type_label" do
    it "returns General for blank" do
      expect(described_class.event_type_label(nil)).to eq("General")
      expect(described_class.event_type_label("")).to eq("General")
    end

    it "returns configured labels for current slugs" do
      expect(described_class.event_type_label("pvp")).to eq("PvP")
      expect(described_class.event_type_label("nodewar")).to eq("Nodewar")
      expect(described_class.event_type_label("raidboss")).to eq("Raidboss")
    end

    it "returns legacy labels" do
      expect(described_class.event_type_label("guild_scrim")).to eq("Guild Scrim")
    end
  end

  describe "event_type validation" do
    let(:guild) { create(:guild) }
    let(:alliance) { create(:alliance, leader_guild: guild, leader_user: guild.owner) }
    let(:user) { guild.owner }

    it "allows blank event_type" do
      event = build(:alliance_event, alliance: alliance, created_by: user, event_type: nil)
      expect(event).to be_valid
    end

    it "allows legacy slugs" do
      event = build(:alliance_event, alliance: alliance, created_by: user, event_type: "gvg")
      expect(event).to be_valid
    end

    it "allows new slugs" do
      event = build(:alliance_event, alliance: alliance, created_by: user, event_type: "alliance_quest")
      expect(event).to be_valid
    end

    it "rejects unknown slugs" do
      event = build(:alliance_event, alliance: alliance, created_by: user, event_type: "totally_unknown")
      expect(event).not_to be_valid
    end
  end

  describe "#role_categories_for_discord" do
    let(:guild) { create(:guild) }
    let(:alliance) { create(:alliance, leader_guild: guild, leader_user: guild.owner) }
    let(:user) { guild.owner }
    let(:event) { build(:alliance_event, alliance: alliance, created_by: user) }
    let(:allowed) { AllianceDiscordBroadcastService::ROLE_CATEGORIES }

    it "uses defaults when role_categories is blank" do
      allow(event).to receive(:role_categories).and_return(nil)
      expect(event.role_categories_for_discord).to eq(allowed)
    end

    it "intersects stored categories with allowed Discord roles" do
      allow(event).to receive(:role_categories).and_return(%w[dps tank bogus])
      expect(event.role_categories_for_discord).to eq(%w[dps tank])
    end

    it "parses a JSON array string and intersects" do
      allow(event).to receive(:role_categories).and_return('["healer","ranged","x"]')
      expect(event.role_categories_for_discord).to eq(%w[healer ranged])
    end

    it "falls back to defaults when role_categories string is not valid JSON" do
      allow(event).to receive(:role_categories).and_return("{not json")
      expect(event.role_categories_for_discord).to eq(allowed)
    end
  end
end
