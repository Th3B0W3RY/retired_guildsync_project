# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guild, type: :model do
  let!(:free_plan) { create(:pricing_plan, name: "Free", max_guilds: 1, max_members_per_guild: 10) }
  let(:user) { create(:user) }

  describe "validations" do
    it "requires a name" do
      guild = build(:guild, owner: user, name: nil)
      expect(guild).not_to be_valid
      expect(guild.errors[:name]).to be_present
    end

    it "requires name to be at least 3 characters" do
      guild = build(:guild, owner: user, name: "ab")
      expect(guild).not_to be_valid
      expect(guild.errors[:name]).to be_present
    end

    it "requires name to be at most 100 characters" do
      guild = build(:guild, owner: user, name: "a" * 101)
      expect(guild).not_to be_valid
      expect(guild.errors[:name]).to be_present
    end

    it "validates description length" do
      guild = build(:guild, owner: user, description: "a" * 1001)
      expect(guild).not_to be_valid
      expect(guild.errors[:description]).to be_present
    end

    it "rejects duplicate permission role slots" do
      guild = build(
        :guild,
        owner: user,
        permission_role_1_id: "discord-role-1",
        permission_role_2_id: "discord-role-1"
      )

      expect(guild).not_to be_valid
      expect(guild.errors[:base]).to include("This role has already been selected!")
    end
  end

  describe "associations" do
    it "belongs to an owner" do
      guild = create(:guild, owner: user)
      expect(guild.owner).to eq(user)
    end

    it "has many members through guild_members" do
      guild = create(:guild, owner: user)
      member = create(:user)
      create(:guild_member, guild: guild, user: member)
      expect(guild.members).to include(member)
    end

    it "has many events" do
      guild = create(:guild, owner: user)
      event = create(:event, guild: guild)
      expect(guild.events).to include(event)
    end
  end

  describe "recruiting visibility on create" do
    it "sets publicly_listed false when the name contains a blocked term" do
      guild = build(:guild, owner: user, name: "Test hitler guild", publicly_listed: true)
      guild.valid?
      expect(guild.publicly_listed).to be false
    end

    it "leaves publicly_listed true when the name is clean" do
      guild = build(:guild, owner: user, name: "Clean Name Guild", publicly_listed: true)
      guild.valid?
      expect(guild.publicly_listed).to be true
    end
  end

  describe ".publicly_listed scope" do
    it "includes guilds where publicly_listed is true" do
      guild = create(:guild, owner: user, publicly_listed: true)
      expect(Guild.publicly_listed).to include(guild)
    end

    it "excludes guilds where publicly_listed is false" do
      guild = create(:guild, owner: user, publicly_listed: false)
      expect(Guild.publicly_listed).not_to include(guild)
    end

    it "defaults to true for new guilds" do
      guild = create(:guild, owner: user)
      expect(guild.publicly_listed).to be true
    end
  end

  describe "cascade deletions" do
    let(:guild) { create(:guild, owner: user) }
    let!(:event) { create(:event, guild: guild, created_by: user) }
    let!(:guild_member) { create(:guild_member, guild: guild, user: create(:user)) }

    it "deletes associated records when guild is deleted" do
      guild_id = guild.id
      # Add owner as member (as done in controller)
      create(:guild_member, guild: guild, user: user, role: :owner) unless guild.guild_members.exists?(user: user)
      
      expect(Event.where(guild_id: guild_id).count).to eq(1)
      expect(GuildMember.where(guild_id: guild_id).count).to eq(2) # owner + member

      guild.destroy

      expect(Event.where(guild_id: guild_id).count).to eq(0)
      expect(GuildMember.where(guild_id: guild_id).count).to eq(0)
    end
  end

  describe "archive lifecycle" do
    let(:guild) { create(:guild, owner: user) }

    it "archives and schedules purge one year out" do
      now = Time.current
      guild.archive!(actor: user)
      guild.reload

      expect(guild.archived_at).to be_within(2.seconds).of(now)
      expect(guild.scheduled_purge_at).to be_within(2.seconds).of(now + 1.year)
    end

    it "blocks unarchive when owner's plan limit is reached" do
      limited_plan = create(:pricing_plan, name: "Limit 1", max_guilds: 2, price: 10, price_display: "$10", period: "month")
      user.subscribe_to_plan!(limited_plan)
      active_guild = create(:guild, owner: user)
      archived_guild = create(:guild, owner: user, archived_at: 2.days.ago, scheduled_purge_at: 1.year.from_now)
      limited_plan.update!(max_guilds: 1)
      user.reload
      expect(active_guild).to be_present

      expect { archived_guild.unarchive!(actor: user) }.to raise_error(ArgumentError)
    end

    it "reports purge eligibility only after retention period" do
      guild.update!(archived_at: Time.current, scheduled_purge_at: 1.day.from_now)
      expect(guild.eligible_for_purge?).to be false

      guild.update!(scheduled_purge_at: 1.minute.ago)
      expect(guild.eligible_for_purge?).to be true
    end
  end

  describe "#discord_server_display_name" do
    it "uses connected Discord server name when present" do
      guild = create(:guild, owner: user, name: "App Guild Name")
      create(:guild_discord_setting, guild: guild, discord_guild_name: "Discord Server Name")
      expect(guild.discord_server_display_name).to eq("Discord Server Name")
    end

    it "falls back to app guild name when Discord name is blank" do
      guild = create(:guild, owner: user, name: "App Only")
      create(:guild_discord_setting, guild: guild, discord_guild_name: nil)
      expect(guild.discord_server_display_name).to eq("App Only")
    end
  end

  describe "#role_permission_enabled_for?" do
    let(:guild) { create(:guild, owner: user) }
    let(:slot_discord_role_id) { "slot_discord_role_policy_spec" }
    let(:member_user) { create(:user) }

    before do
      create(:guild_member, guild: guild, user: member_user, role: :member, status: :active,
                            discord_role_id: slot_discord_role_id)
    end

    it "returns true for the guild owner regardless of slot flags" do
      expect(guild.role_permission_enabled_for?(user, :can_manage_discord_channels)).to be true
    end

    it "returns false for nil user" do
      expect(guild.role_permission_enabled_for?(nil, :can_manage_discord_channels)).to be false
    end

    it "returns false when the matching slot flag is off" do
      guild.update!(permission_role_1_id: slot_discord_role_id, role_1_can_manage_discord_channels: false)
      expect(guild.role_permission_enabled_for?(member_user, :can_manage_discord_channels)).to be false
    end

    it "returns true when the member Discord role matches the slot and the flag is on" do
      guild.update!(permission_role_1_id: slot_discord_role_id, role_1_can_manage_discord_channels: true)
      expect(guild.role_permission_enabled_for?(member_user, :can_manage_discord_channels)).to be true
    end
  end
end
