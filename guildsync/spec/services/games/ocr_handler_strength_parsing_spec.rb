# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OCR handler strength parsing" do
  describe Games::FinalFantasyXiv::OcrHandler do
    it "parses Strength when OCR drops letters in the label" do
      raw_text = <<~TEXT
        Stength
        120
        Dexterity
        130
      TEXT

      data = described_class.parse_gear_data(raw_text, {}, {})
      expect(data["Strength"]).to eq(120)
      expect(data["Dexterity"]).to eq(130)
    end
  end

  describe Games::Maplestory2::OcrHandler do
    it "parses STR when OCR reads it as SIR" do
      raw_text = <<~TEXT
        SIR (*)
        2,694
        DEX
        2,100
      TEXT

      data = described_class.parse_gear_data(raw_text, {}, {})
      expect(data["STR"]).to eq(2694)
      expect(data["DEX"]).to eq(2100)
    end

    it "parses LUK from nearby numeric line when value is displaced" do
      raw_text = <<~TEXT
        DEX
        22,930
        1,481
        LUK
        EKOS:
        INT
        1,521
      TEXT

      data = described_class.parse_gear_data(raw_text, {}, {})
      expect(data["LUK"]).to eq(1481)
      expect(data["INT"]).to eq(1521)
    end

    it "parses ATTACK POWER when value has a leading minus sign" do
      raw_text = <<~TEXT
        ATTACK POWER
        - 1,404
      TEXT

      data = described_class.parse_gear_data(raw_text, {}, {})
      expect(data["ATTACK POWER"]).to eq(1404)
    end
  end

  describe Games::WorldOfWarcraft::OcrHandler do
    it "parses Strength when OCR reads it as Strengh" do
      raw_text = <<~TEXT
        Level 60
        Strengh
        125
        Agility
        112
      TEXT

      data = described_class.parse_gear_data(raw_text, {}, {})
      expect(data["Strength"]).to eq(125)
      expect(data["Agility"]).to eq(112)
    end

    it "parses Strength when a bracketed mount line appears between label and value" do
      raw_text = <<~TEXT
        Strength:
        [1] on mount
        139
        Agility:
        177
      TEXT

      data = described_class.parse_gear_data(raw_text, {}, {})
      expect(data["Strength"]).to eq(139)
      expect(data["Agility"]).to eq(177)
    end
  end
end
