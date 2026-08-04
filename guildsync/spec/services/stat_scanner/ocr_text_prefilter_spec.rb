# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatScanner::OcrTextPrefilter do
  describe ".filter_for_stat_scan" do
    it "removes MMO chat-style lines with bracket channel and speaker: message" do
      text = <<~TEXT.strip
        [Guild] SomePlayer: hello world
        Strength: 1452
        Melee Attack 2680.14
      TEXT
      out = described_class.filter_for_stat_scan(text)
      expect(out).not_to include("SomePlayer")
      expect(out).to include("Strength: 1452")
      expect(out).to include("Melee Attack")
    end

    it "passes through unchanged when no chat lines" do
      text = "Stamina: 178\nAgility 68"
      expect(described_class.filter_for_stat_scan(text)).to eq(text)
    end

    it "removes double-bracket chat-style lines" do
      text = <<~TEXT.strip
        [2. Trade] [SomePlayer]: selling orb
        Strength: 1452
      TEXT
      out = described_class.filter_for_stat_scan(text)
      expect(out).not_to include("SomePlayer")
      expect(out).to include("Strength: 1452")
    end
  end
end
