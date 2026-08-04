# frozen_string_literal: true

require "rails_helper"

RSpec.describe Alliance, type: :model do
  let(:owner)  { create(:user) }
  let(:guild)  { create(:guild, owner: owner) }
  let(:alliance) do
    a = build(:alliance, leader_guild: guild, leader_user: owner)
    a.save!
    a
  end

  describe "validations" do
    it "is valid with valid attributes" do
      expect(alliance).to be_valid
    end

    it "requires a name" do
      alliance.name = nil
      expect(alliance).not_to be_valid
    end

    it "requires name length between 2 and 60" do
      alliance.name = "A"
      expect(alliance).not_to be_valid
      alliance.name = "A" * 61
      expect(alliance).not_to be_valid
    end

    it "rejects a non-image logo attachment" do
      alliance.logo.attach(
        io: StringIO.new("not an image"),
        filename: "note.txt",
        content_type: "text/plain"
      )
      expect(alliance).not_to be_valid
      expect(alliance.errors[:logo]).to be_present
    end
  end

  describe "enums" do
    it "has active and disbanded statuses" do
      expect(Alliance.statuses.keys).to contain_exactly("active", "disbanded")
    end
  end

  describe "#active_guild_count" do
    it "counts active alliance_guilds" do
      create(:alliance_guild, alliance: alliance, guild: guild, status: :active)
      expect(alliance.active_guild_count).to eq(1)
    end
  end

  describe "#can_add_more_guilds?" do
    it "returns true when fewer than 20 guilds" do
      expect(alliance.can_add_more_guilds?).to be true
    end
  end

  describe "#majority_voted_to_disband?" do
    let(:guild2)  { create(:guild) }
    let(:guild3)  { create(:guild) }

    before do
      create(:alliance_guild, alliance: alliance, guild: guild, status: :active)
      create(:alliance_guild, alliance: alliance, guild: guild2, status: :active)
      create(:alliance_guild, alliance: alliance, guild: guild3, status: :active)
    end

    it "returns false when no votes cast" do
      expect(alliance.majority_voted_to_disband?).to be false
    end

    it "returns false when minority votes to disband" do
      create(:alliance_disband_vote, alliance: alliance, user: owner, guild: guild, vote: true)
      expect(alliance.majority_voted_to_disband?).to be false
    end

    it "returns true when majority vote to disband" do
      create(:alliance_disband_vote, alliance: alliance, user: owner,          guild: guild,  vote: true)
      create(:alliance_disband_vote, alliance: alliance, user: guild2.owner,   guild: guild2, vote: true)
      expect(alliance.majority_voted_to_disband?).to be true
    end
  end

  describe "#disband!" do
    before do
      create(:alliance_guild, alliance: alliance, guild: guild, status: :active)
      create(:alliance_member, alliance: alliance, user: owner, guild: guild, status: :active)
    end

    it "marks the alliance as disbanded" do
      alliance.disband!
      expect(alliance.reload).to be_disbanded
    end

    it "marks active guilds as left" do
      alliance.disband!
      expect(alliance.alliance_guilds.pluck(:status)).to all(eq("left"))
    end

    it "marks active members as removed" do
      alliance.disband!
      expect(alliance.alliance_members.pluck(:status)).to all(eq("removed"))
    end
  end
end
