# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatScanner::StatRows do
  describe ".from_data" do
    it "builds one row per hash entry in insertion order" do
      data = { "Melee Attack" => "100", "Ranged Attack" => "200" }
      rows = described_class.from_data(data)
      expect(rows.map { |r| [r.label, r.value] }).to eq([
        ["Melee Attack", "100"],
        ["Ranged Attack", "200"]
      ])
    end

    it "returns empty array for nil" do
      expect(described_class.from_data(nil)).to eq([])
    end

    it "returns empty array for empty hash" do
      expect(described_class.from_data({})).to eq([])
    end

    it "formats numeric and boolean values as strings" do
      rows = described_class.from_data({ "Level" => 40, "Flag" => true })
      expect(rows.find { |r| r.label == "Level" }.value).to eq("40")
      expect(rows.find { |r| r.label == "Flag" }.value).to eq("true")
    end

    it "uses unnamed_stat label when key is blank but value present" do
      rows = described_class.from_data({ "" => "orphan" })
      expect(rows.size).to eq(1)
      expect(rows.first.key).to eq("")
      expect(rows.first.label).to eq(I18n.t("guilds.member_stats.unnamed_stat"))
      expect(rows.first.value).to eq("orphan")
    end

    it "wraps non-hash data as a single unparsed row" do
      rows = described_class.from_data("raw blob")
      expect(rows.size).to eq(1)
      expect(rows.first.label).to eq(I18n.t("guilds.member_stats.unparsed_label"))
      expect(rows.first.value).to eq("raw blob")
    end
  end
end
