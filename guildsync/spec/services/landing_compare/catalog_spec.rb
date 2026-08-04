# frozen_string_literal: true

require "rails_helper"

RSpec.describe LandingCompare::Catalog do
  describe "ROWS" do
    it "includes custom_role_system with GuildSync-only positioning defaults" do
      row = described_class::ROWS.find { |r| r[:key] == "custom_role_system" }
      expect(row).to be_present
      expect(row[:label]).to eq("Custom Role System")
      expect(row[:guild_manager]).to be false
      expect(row[:guild_spire]).to be false
      expect(row[:typical]).to be false
    end
  end

  describe ".competitor_included?" do
    it "returns false for custom_role_system on every competitor column" do
      expect(described_class.competitor_included?(0, "custom_role_system")).to be false
      expect(described_class.competitor_included?(1, "custom_role_system")).to be false
      expect(described_class.competitor_included?(2, "custom_role_system")).to be false
    end
  end
end
