# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountDeletion::EligibilityChecker do
  describe "#call" do
    it "allows a user with no blocking guild or alliance state" do
      user = create(:user, email: "elig-ok-#{SecureRandom.hex(4)}@example.com")
      result = described_class.new(user).call
      expect(result.allowed?).to be true
    end

    it "disallows when the user is archived" do
      user = create(:user, email: "elig-arch-#{SecureRandom.hex(4)}@example.com", archived: true)
      result = described_class.new(user).call
      expect(result).to have_attributes(allowed?: false, reason: :already_closed)
    end

    it "disallows when the user leads an active alliance" do
      owner = create(:user, email: "elig-ally-#{SecureRandom.hex(4)}@example.com")
      guild = create(:guild, owner: owner)
      user = guild.owner
      create(:alliance, leader_guild: guild, leader_user: user)

      result = described_class.new(user).call
      expect(result).to have_attributes(allowed?: false, reason: :alliance_leader)
    end

    it "disallows when the user owns a non-archived guild with other active members" do
      owner = create(:user, email: "elig-own-#{SecureRandom.hex(4)}@example.com")
      guild = create(:guild, owner: owner)
      other = create(:user, email: "elig-mem-#{SecureRandom.hex(4)}@example.com")
      create(:guild_member, guild: guild, user: other, role: :member, status: :active)

      result = described_class.new(owner).call
      expect(result).to have_attributes(allowed?: false, reason: :owned_guild_has_members)
    end

    it "allows when the user owns a guild with inactive co-members only" do
      owner = create(:user, email: "elig-inactive-#{SecureRandom.hex(4)}@example.com")
      guild = create(:guild, owner: owner)
      other = create(:user, email: "elig-inactm-#{SecureRandom.hex(4)}@example.com")
      create(:guild_member, guild: guild, user: other, role: :member, status: :inactive)

      result = described_class.new(owner).call
      expect(result.allowed?).to be true
    end

    it "disallows when closure processing was started without a completed soft-close row (edge case)" do
      user = create(:user, email: "elig-prog-#{SecureRandom.hex(4)}@example.com")
      user.update_columns(account_deletion_started_at: Time.current, updated_at: Time.current)
      result = described_class.new(user).call
      expect(result).to have_attributes(allowed?: false, reason: :purge_in_progress)
    end
  end
end
