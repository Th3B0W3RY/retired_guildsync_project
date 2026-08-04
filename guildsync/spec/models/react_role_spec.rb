# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReactRole, type: :model do
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let!(:synced_role) { create(:discord_role_sync, guild: guild, role_id: "12345678901234567") }

  # ──────────────────────────────────────────────────────────────────────────
  # Associations
  # ──────────────────────────────────────────────────────────────────────────

  describe "associations" do
    it "belongs to guild" do
      expect(described_class.reflect_on_association(:guild).macro).to eq(:belongs_to)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Validations
  # ──────────────────────────────────────────────────────────────────────────

  describe "validations" do
    subject { build(:react_role, guild: guild, role_id: synced_role.role_id) }

    it "requires position" do
      rr = build(:react_role, guild: guild, role_id: synced_role.role_id, position: nil)
      expect(rr).not_to be_valid
      expect(rr.errors[:position]).to be_present
    end

    it "requires role_id" do
      rr = build(:react_role, guild: guild, role_id: nil, position: 1)
      expect(rr).not_to be_valid
      expect(rr.errors[:role_id]).to be_present
    end

    it "requires role_name" do
      rr = build(:react_role, guild: guild, role_id: synced_role.role_id, role_name: nil, position: 1)
      expect(rr).not_to be_valid
      expect(rr.errors[:role_name]).to be_present
    end

    it "requires emoji_name" do
      rr = build(:react_role, guild: guild, role_id: synced_role.role_id, emoji_name: nil, position: 1)
      expect(rr).not_to be_valid
      expect(rr.errors[:emoji_name]).to be_present
    end

    context "position" do
      it "accepts 1, 2, 3" do
        [1, 2, 3].each do |pos|
          rr = build(:react_role, guild: guild, position: pos, role_id: synced_role.role_id)
          expect(rr).to be_valid, "expected position #{pos} to be valid"
        end
      end

      it "rejects 0" do
        rr = build(:react_role, guild: guild, position: 0, role_id: synced_role.role_id)
        expect(rr).not_to be_valid
        expect(rr.errors[:position]).to be_present
      end

      it "rejects 4" do
        rr = build(:react_role, guild: guild, position: 4, role_id: synced_role.role_id)
        expect(rr).not_to be_valid
        expect(rr.errors[:position]).to be_present
      end

      it "enforces uniqueness of position per guild" do
        create(:react_role, guild: guild, position: 1, role_id: synced_role.role_id)
        duplicate = build(:react_role, guild: guild, position: 1, role_id: synced_role.role_id)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:position]).to be_present
      end

      it "allows the same position in a different guild" do
        other_guild = create(:guild, owner: create(:user))
        other_synced_role = create(:discord_role_sync, guild: other_guild)
        create(:react_role, guild: guild, position: 1, role_id: synced_role.role_id)
        rr = build(:react_role, guild: other_guild, position: 1, role_id: other_synced_role.role_id)
        expect(rr).to be_valid
      end
    end

    context "role_must_be_synced" do
      it "is invalid when role_id is not in discord_role_syncs" do
        rr = build(:react_role, guild: guild, role_id: "nonexistent_role_id")
        expect(rr).not_to be_valid
        expect(rr.errors[:role_id]).to include(a_string_matching(/synced/))
      end

      it "is valid when role_id matches a synced role" do
        rr = build(:react_role, guild: guild, role_id: synced_role.role_id)
        expect(rr).to be_valid
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Scopes
  # ──────────────────────────────────────────────────────────────────────────

  describe ".ordered" do
    it "returns react_roles sorted by position" do
      r3 = create(:react_role, guild: guild, position: 3, role_id: synced_role.role_id)
      r1 = create(:react_role, guild: guild, position: 1, role_id: synced_role.role_id)
      r2 = create(:react_role, guild: guild, position: 2, role_id: synced_role.role_id)

      expect(ReactRole.ordered.to_a).to eq([r1, r2, r3])
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Instance methods
  # ──────────────────────────────────────────────────────────────────────────

  describe "#display_emoji" do
    context "with a unicode emoji" do
      subject { build(:react_role, guild: guild, emoji_name: "🔥", is_custom_emoji: false) }
      it "returns the raw character" do
        expect(subject.display_emoji).to eq("🔥")
      end
    end

    context "with a custom emoji" do
      subject { build(:react_role, :custom_emoji, guild: guild, role_id: synced_role.role_id) }
      it "returns the Discord embed format" do
        expect(subject.display_emoji).to eq("<:LUL:41771983429993937>")
      end
    end
  end

  describe "#api_emoji" do
    context "with a unicode emoji" do
      subject { build(:react_role, guild: guild, emoji_name: "🔥", is_custom_emoji: false) }
      it "returns the raw character" do
        expect(subject.api_emoji).to eq("🔥")
      end
    end

    context "with a custom emoji" do
      subject { build(:react_role, :custom_emoji, guild: guild, role_id: synced_role.role_id) }
      it "returns name:id format" do
        expect(subject.api_emoji).to eq("LUL:41771983429993937")
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Guild association
  # ──────────────────────────────────────────────────────────────────────────

  describe "Guild#react_roles" do
    it "destroys react_roles when the guild is destroyed" do
      rr = create(:react_role, guild: guild, role_id: synced_role.role_id)
      expect { guild.destroy }.to change { ReactRole.count }.by(-1)
    end
  end
end
