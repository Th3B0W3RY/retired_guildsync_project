# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildPolicy, type: :policy do
  subject { described_class }

  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }
  let(:owner) { create(:user) }
  let(:guild) { create(:guild, owner: owner) }
  let(:member) { create(:user) }
  let(:admin) { create(:user) }
  let!(:member_record) { create(:guild_member, guild: guild, user: member, role: :member, status: :active) }
  let!(:admin_record) { create(:guild_member, guild: guild, user: admin, role: :admin, status: :active) }

  describe "#index?" do
    it "allows access for guests" do
      policy = described_class.new(nil, guild)
      expect(policy.index?).to be true
    end
  end

  describe "#show?" do
    it "allows access for guests when guild is publicly listed" do
      policy = described_class.new(nil, guild)
      expect(policy.show?).to be true
    end

    it "denies guests when guild is not publicly listed" do
      guild.update!(publicly_listed: false)
      policy = described_class.new(nil, guild)
      expect(policy.show?).to be false
    end

    it "allows the guild owner" do
      policy = described_class.new(owner, guild)
      expect(policy.show?).to be true
    end

    it "allows active members" do
      policy = described_class.new(member, guild)
      expect(policy.show?).to be true
    end

    it "denies unrelated authenticated users when the guild is not publicly listed" do
      guild.update!(publicly_listed: false)
      stranger = create(:user)
      policy = described_class.new(stranger, guild)
      expect(policy.show?).to be false
    end
  end

  describe "#create?" do
    it "allows authenticated users" do
      policy = described_class.new(member, Guild)
      expect(policy.create?).to be true
    end

    it "denies guests" do
      policy = described_class.new(nil, Guild)
      expect(policy.create?).to be false
    end
  end

  describe "#update?" do
    it "allows the guild owner" do
      policy = described_class.new(owner, guild)
      expect(policy.update?).to be true
    end

    it "allows guild admins" do
      policy = described_class.new(admin, guild)
      expect(policy.update?).to be true
    end

    it "denies regular members" do
      policy = described_class.new(member, guild)
      expect(policy.update?).to be false
    end
  end

  describe "#destroy?" do
    it "allows only the guild owner" do
      policy = described_class.new(owner, guild)
      expect(policy.destroy?).to be true
      
      policy = described_class.new(admin, guild)
      expect(policy.destroy?).to be false
      
      policy = described_class.new(member, guild)
      expect(policy.destroy?).to be false
    end
  end

  describe "#manage_discord? and #update_discord_channels?" do
    let(:slot_id) { "policy_spec_discord_role_slot" }

    it "allow the guild owner" do
      policy = described_class.new(owner, guild)
      expect(policy.manage_discord?).to be true
      expect(policy.update_discord_channels?).to be true
    end

    it "deny admins and members without a matching Discord role on the guild" do
      policy = described_class.new(admin, guild)
      expect(policy.manage_discord?).to be false
      expect(policy.update_discord_channels?).to be false

      policy = described_class.new(member, guild)
      expect(policy.manage_discord?).to be false
      expect(policy.update_discord_channels?).to be false
    end

    it "allow a member whose discord_role_id matches permission_role_1 when role_1_can_manage_discord_channels is true" do
      guild.update!(permission_role_1_id: slot_id, role_1_can_manage_discord_channels: true)
      member_record.update!(discord_role_id: slot_id)

      policy = described_class.new(member, guild)
      expect(policy.manage_discord?).to be true
      expect(policy.update_discord_channels?).to be true
    end

    it "deny when the slot flag is false even when discord_role_id matches" do
      guild.update!(permission_role_1_id: slot_id, role_1_can_manage_discord_channels: false)
      member_record.update!(discord_role_id: slot_id)

      policy = described_class.new(member, guild)
      expect(policy.manage_discord?).to be false
      expect(policy.update_discord_channels?).to be false
    end
  end

  describe "#signup_discord_event_participation?" do
    it "allows the guild owner" do
      expect(described_class.new(owner, guild).signup_discord_event_participation?).to be true
    end

    it "allows an active member" do
      expect(described_class.new(member, guild).signup_discord_event_participation?).to be true
    end

    it "denies guests" do
      expect(described_class.new(nil, guild).signup_discord_event_participation?).to be false
    end

    it "denies users who are not members" do
      stranger = create(:user)
      expect(described_class.new(stranger, guild).signup_discord_event_participation?).to be false
    end

    it "denies inactive members" do
      member_record.update!(status: :inactive)
      expect(described_class.new(member, guild).signup_discord_event_participation?).to be false
    end
  end
end

