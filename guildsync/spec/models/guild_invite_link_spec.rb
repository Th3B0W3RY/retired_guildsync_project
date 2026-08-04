# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildInviteLink, type: :model do
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }

  describe "token generation" do
    it "auto-generates a token on create" do
      link = guild.guild_invite_links.create!(created_by: owner)
      expect(link.token).to be_present
      expect(link.token.length).to be >= 24
    end

    it "does not overwrite a manually set token" do
      link = guild.guild_invite_links.create!(created_by: owner, token: "custom-token-123")
      expect(link.token).to eq("custom-token-123")
    end

    it "enforces token uniqueness" do
      guild.guild_invite_links.create!(created_by: owner, token: "unique-tok")
      dup = guild.guild_invite_links.new(created_by: owner, token: "unique-tok")
      expect(dup).not_to be_valid
      expect(dup.errors[:token]).to include("has already been taken")
    end
  end

  describe ".find_by_token" do
    it "finds a link by its token string" do
      link = guild.guild_invite_links.create!(created_by: owner)
      expect(described_class.find_by_token(link.token)).to eq(link)
    end

    it "returns nil for a non-existent token" do
      expect(described_class.find_by_token("nonexistent")).to be_nil
    end

    it "returns nil for a blank token" do
      expect(described_class.find_by_token("")).to be_nil
      expect(described_class.find_by_token(nil)).to be_nil
    end
  end

  describe "#expired?" do
    it "returns false when expires_at is nil" do
      link = guild.guild_invite_links.create!(created_by: owner, expires_at: nil)
      expect(link.expired?).to be false
    end

    it "returns false when expires_at is in the future" do
      link = guild.guild_invite_links.create!(created_by: owner, expires_at: 1.hour.from_now)
      expect(link.expired?).to be false
    end

    it "returns true when expires_at is in the past" do
      link = guild.guild_invite_links.create!(created_by: owner, expires_at: 1.minute.ago)
      expect(link.expired?).to be true
    end

    it "returns true when expires_at is in the past (boundary)" do
      link = guild.guild_invite_links.create!(created_by: owner, expires_at: 1.second.ago)
      expect(link.expired?).to be true
    end
  end

  describe "#usable?" do
    it "returns true when not expired" do
      link = guild.guild_invite_links.create!(created_by: owner, expires_at: 1.day.from_now)
      expect(link.usable?).to be true
    end

    it "returns false when expired" do
      link = guild.guild_invite_links.create!(created_by: owner, expires_at: 1.day.ago)
      expect(link.usable?).to be false
    end

    it "returns true when expires_at is nil (no expiry)" do
      link = guild.guild_invite_links.create!(created_by: owner, expires_at: nil)
      expect(link.usable?).to be true
    end
  end
end
