# frozen_string_literal: true

require "rails_helper"

RSpec.describe GearSnapshots::UpdateExtractedData do
  let(:guild) { create(:guild) }
  let(:user) { create(:user, auth_method: :discord) }
  let(:game) { guild.games.first }
  let(:snapshot) do
    create(:gear_snapshot, guild: guild, user: user, game: game, data: { "Stamina" => "42", "Power" => 9001 })
  end

  describe ".call" do
    it "removes an existing key" do
      result = described_class.call(snapshot: snapshot, operation: "remove", stat_key: "Stamina")
      expect(result.success?).to be true
      expect(snapshot.reload.data).to eq("Power" => 9001)
    end

    it "restores a key with scalar values" do
      snapshot.update!(data: { "Power" => 1 })
      result = described_class.call(
        snapshot: snapshot,
        operation: "restore",
        stat_key: "Stamina",
        stat_value: "99"
      )
      expect(result.success?).to be true
      expect(snapshot.reload.data["Stamina"]).to eq("99")
    end

    it "rejects restore when key already exists" do
      result = described_class.call(
        snapshot: snapshot,
        operation: "restore",
        stat_key: "Stamina",
        stat_value: "1"
      )
      expect(result).not_to be_success
      expect(result.code).to eq(:key_exists)
    end

    it "rejects remove when key is missing" do
      result = described_class.call(snapshot: snapshot, operation: "remove", stat_key: "Missing")
      expect(result).not_to be_success
      expect(result.code).to eq(:missing_key)
    end

    it "rejects nested stat_value" do
      snapshot.update!(data: {})
      result = described_class.call(
        snapshot: snapshot,
        operation: "restore",
        stat_key: "X",
        stat_value: { "a" => 1 }
      )
      expect(result).not_to be_success
      expect(result.code).to eq(:complex_type)
    end

    it "updates label and value in place" do
      result = described_class.call(
        snapshot: snapshot,
        operation: "update",
        stat_key: "Stamina",
        stat_label: "Stamina",
        stat_value: "100"
      )
      expect(result.success?).to be true
      expect(result.new_stat_key).to eq("Stamina")
      expect(snapshot.reload.data).to eq("Stamina" => "100", "Power" => 9001)
    end

    it "renames a stat key" do
      result = described_class.call(
        snapshot: snapshot,
        operation: "update",
        stat_key: "Stamina",
        stat_label: "Energy",
        stat_value: "42"
      )
      expect(result.success?).to be true
      expect(result.new_stat_key).to eq("Energy")
      expect(snapshot.reload.data).to eq("Energy" => "42", "Power" => 9001)
    end

    it "rejects update when new key collides" do
      result = described_class.call(
        snapshot: snapshot,
        operation: "update",
        stat_key: "Stamina",
        stat_label: "Power",
        stat_value: "1"
      )
      expect(result).not_to be_success
      expect(result.code).to eq(:key_exists)
    end

    it "rejects update without stat_label" do
      result = described_class.call(
        snapshot: snapshot,
        operation: "update",
        stat_key: "Stamina",
        stat_value: "1"
      )
      expect(result).not_to be_success
      expect(result.code).to eq(:missing_label)
    end
  end
end
