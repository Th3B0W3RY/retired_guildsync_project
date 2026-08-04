# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecruitingVisibilityService, type: :service do
  describe ".publicly_recruitable?" do
    it "returns true for blank string" do
      expect(described_class.publicly_recruitable?("")).to be true
      expect(described_class.publicly_recruitable?("   ")).to be true
    end

    it "returns true when guild name is blank" do
      guild = build(:guild, name: "")
      expect(described_class.publicly_recruitable?(guild)).to be true
    end

    it "returns true when name has no blocklist substring" do
      expect(described_class.publicly_recruitable?("Honest Adventurers")).to be true
    end

    it "returns false when name includes a blocklist word (case insensitive)" do
      expect(described_class.publicly_recruitable?("We are NOT nazis")).to be false
      expect(described_class.publicly_recruitable?("HITLER was bad")).to be false
      expect(described_class.publicly_recruitable?("no kkk here")).to be false
      expect(described_class.publicly_recruitable?("slur recovery guild")).to be false
    end

    it "accepts a Guild and uses its name" do
      clean = build(:guild, name: "Safe Name")
      blocked = build(:guild, name: "blocked kkk tag")

      expect(described_class.publicly_recruitable?(clean)).to be true
      expect(described_class.publicly_recruitable?(blocked)).to be false
    end

    it "documents every configured blocklist entry is detected as substring" do
      described_class::BLOCKLIST.each do |word|
        expect(described_class.publicly_recruitable?("prefix_#{word}_suffix")).to be(false),
          "expected #{word.inspect} to match as substring"
      end
    end
  end

  describe ".matching_severe_terms" do
    it "returns empty when all strings are blank" do
      expect(described_class.matching_severe_terms("", nil)).to eq([])
    end

    it "returns blocklist tokens found as substrings across arguments (case insensitive)" do
      expect(described_class.matching_severe_terms("Clean", "about NAZI history")).to eq([ "nazi" ])
      expect(described_class.matching_severe_terms("kkk in title", "ok")).to eq([ "kkk" ])
    end

    it "returns multiple distinct hits without duplicates" do
      expect(described_class.matching_severe_terms("nazi and kkk", "")).to contain_exactly("nazi", "kkk")
    end
  end
end
