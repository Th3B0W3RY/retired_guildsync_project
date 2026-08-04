# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventPolicy, type: :policy do
  subject { described_class }

  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }
  let(:guild_owner) { create(:user) }
  let(:guild) { create(:guild, owner: guild_owner) }
  let(:creator) { create(:user) }
  let(:admin) { create(:user) }
  let(:member) { create(:user) }
  let(:outsider) { create(:user) }

  # Owner membership is automatically created by guild factory, so we just need to ensure it exists
  let!(:owner_membership) { guild.guild_members.find_by(user: guild_owner) || create(:guild_member, guild: guild, user: guild_owner, role: :owner, status: :active) }
  let!(:creator_membership) { create(:guild_member, guild: guild, user: creator, role: :member, status: :active) }
  let!(:admin_membership) { create(:guild_member, guild: guild, user: admin, role: :admin, status: :active) }
  let!(:member_membership) { create(:guild_member, guild: guild, user: member, role: :member, status: :active) }

  let(:event) { create(:event, guild: guild, created_by: creator) }

  describe "#index?" do
    it "allows signed-in users" do
      expect(described_class.new(outsider, event).index?).to be true
    end

    it "denies guests" do
      expect(described_class.new(nil, event).index?).to be false
    end
  end

  describe "#show?" do
    it "allows guild owner and active members" do
      expect(described_class.new(guild_owner, event).show?).to be true
      expect(described_class.new(member, event).show?).to be true
    end

    it "denies outsiders and guests" do
      expect(described_class.new(outsider, event).show?).to be false
      expect(described_class.new(nil, event).show?).to be false
    end
  end

  describe "#create?" do
    it "allows active guild members" do
      new_event = build(:event, guild: guild, created_by: member)
      policy = described_class.new(member, new_event)
      expect(policy.create?).to be true
    end

    it "allows the guild owner" do
      new_event = build(:event, guild: guild, created_by: guild_owner)
      expect(described_class.new(guild_owner, new_event).create?).to be true
    end

    it "denies non-members" do
      new_event = build(:event, guild: guild, created_by: outsider)
      policy = described_class.new(outsider, new_event)
      expect(policy.create?).to be false
    end

    it "denies guests" do
      new_event = build(:event, guild: guild, created_by: nil)
      policy = described_class.new(nil, new_event)
      expect(policy.create?).to be false
    end
  end

  describe "#update?" do
    it "allows the event creator" do
      policy = described_class.new(creator, event)
      expect(policy.update?).to be true
    end

    it "allows guild admins" do
      policy = described_class.new(admin, event)
      expect(policy.update?).to be true
    end

    it "allows guild owners" do
      # Guild owner should be able to update (checked via record.guild.owner == user)
      policy = described_class.new(guild_owner, event)
      expect(policy.update?).to be true
    end

    it "denies regular members" do
      policy = described_class.new(member, event)
      expect(policy.update?).to be false
    end

    it "denies outsiders" do
      # Outsider is not a member, so find_by returns nil, and nil&.admin? returns nil
      # The policy checks: user.present? && (record.created_by == user || find_by&.admin? || find_by&.owner?)
      # Since outsider is not a member, find_by returns nil, so the expression evaluates to true && (false || nil || nil) = nil
      policy = described_class.new(outsider, event)
      # The policy should return false or nil (both are falsy), but the current implementation returns nil
      expect(policy.update?).to be_falsy
    end
  end

  describe "#destroy?" do
    it "allows the event creator" do
      policy = described_class.new(creator, event)
      expect(policy.destroy?).to be true
    end

    it "allows the guild owner" do
      policy = described_class.new(guild_owner, event)
      expect(policy.destroy?).to be true
    end

    it "denies other members" do
      policy = described_class.new(member, event)
      expect(policy.destroy?).to be false
      
      policy = described_class.new(outsider, event)
      expect(policy.destroy?).to be false
    end
  end
end

