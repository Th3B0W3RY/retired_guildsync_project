# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#show_alliances_top_nav?" do
    let(:user) { create(:user, :discord_auth) }

    it "returns false for nil" do
      expect(helper.show_alliances_top_nav?(nil)).to be false
    end

    it "returns false when user only owns a guild not in an alliance" do
      create(:guild, owner: user)
      expect(helper.show_alliances_top_nav?(user)).to be false
    end

    it "returns true when user has an active alliance membership" do
      g = create(:guild, owner: user)
      a = create(:alliance, leader_guild: g, leader_user: user)
      create(:alliance_guild, alliance: a, guild: g, status: :active, joined_at: Time.current)
      create(:alliance_member, alliance: a, user: user, guild: g, role: :gm, status: :active)
      expect(helper.show_alliances_top_nav?(user)).to be true
    end

    it "returns true when user is a guild member (not owner) of a guild in an active alliance" do
      owner = create(:user, :discord_auth)
      g = create(:guild, owner: owner)
      a = create(:alliance, leader_guild: g, leader_user: owner)
      create(:alliance_guild, alliance: a, guild: g, status: :active, joined_at: Time.current)
      create(:guild_member, guild: g, user: user)
      expect(helper.show_alliances_top_nav?(user)).to be true
    end

    it "returns true when user owns a guild in an active alliance but has no alliance_members row" do
      g = create(:guild, owner: user)
      a = create(:alliance, leader_guild: g, leader_user: user)
      create(:alliance_guild, alliance: a, guild: g, status: :active, joined_at: Time.current)
      expect(helper.show_alliances_top_nav?(user)).to be true
    end

    it "returns true on Basic+ when user has no alliance tie yet (hub entry for create/join flows)" do
      basic = create(:pricing_plan, name: "Basic")
      user.subscriptions.destroy_all
      create(:subscription, user: user, pricing_plan: basic, status: :active)
      create(:guild, owner: user)
      expect(helper.show_alliances_top_nav?(user.reload)).to be true
    end
  end

  describe "#show_nav_create_guild?" do
    let(:user) { create(:user, :discord_auth) }

    it "returns false for nil" do
      expect(helper.show_nav_create_guild?(nil)).to be false
    end

    it "returns true when under plan guild limit" do
      expect(helper.show_nav_create_guild?(user)).to be true
    end

    it "returns false when at plan guild limit" do
      pricing_plan = create(:pricing_plan, max_guilds: 1)
      user.subscriptions.destroy_all
      create(:subscription, user: user, pricing_plan: pricing_plan)
      create(:guild, owner: user)
      user.reload
      expect(helper.show_nav_create_guild?(user)).to be false
    end
  end

  describe "#show_nav_archived_guilds?" do
    let(:user) { create(:user, :discord_auth) }

    it "returns false for nil" do
      expect(helper.show_nav_archived_guilds?(nil)).to be false
    end

    it "returns false when user has never owned a guild" do
      expect(helper.show_nav_archived_guilds?(user)).to be false
    end

    it "returns true when user owns a guild" do
      create(:guild, owner: user)
      expect(helper.show_nav_archived_guilds?(user.reload)).to be true
    end
  end

  describe "#sidebar_discord_username_line" do
    let(:user) { create(:user, :discord_auth) }

    it "returns nil when user has no valid Discord OAuth" do
      expect(helper.sidebar_discord_username_line(user)).to be_nil
    end

    it "returns cleaned username when Discord is connected" do
      create(:user_discord_connection, user: user, discord_username: "player#9876")
      expect(helper.sidebar_discord_username_line(user)).to eq("player")
    end

    it "falls back to site username when connection Discord username is blank" do
      create(:user_discord_connection, user: user, discord_username: nil)
      expect(helper.sidebar_discord_username_line(user)).to eq(user.username)
    end

    it "prefers discord_global_name when connection username is blank" do
      user.update!(discord_global_name: "GlobalNick")
      create(:user_discord_connection, user: user, discord_username: nil)
      expect(helper.sidebar_discord_username_line(user)).to eq("GlobalNick")
    end

    it "uses i18n fallback when no display name is available" do
      create(:user_discord_connection, user: user, discord_username: nil)
      user.update_columns(username: nil, discord_global_name: nil)
      user.reload
      expect(helper.sidebar_discord_username_line(user)).to eq(I18n.t("sidebar.discord_username_fallback"))
    end
  end
end
