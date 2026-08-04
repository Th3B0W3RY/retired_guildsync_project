# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscordGuildMemberLabel do
  describe ".from_member_json" do
    it "prefers server nick over global name" do
      member = {
        "nick" => "RaidLead",
        "user" => { "username" => "login", "global_name" => "Global", "discriminator" => "0" }
      }
      expect(described_class.from_member_json(member)).to eq("RaidLead")
    end

    it "uses global_name when nick is blank" do
      member = {
        "nick" => nil,
        "user" => { "username" => "login", "global_name" => "Display", "discriminator" => "0" }
      }
      expect(described_class.from_member_json(member)).to eq("Display")
    end

    it "uses username without # when discriminator is 0" do
      member = {
        "user" => { "username" => "login", "global_name" => nil, "discriminator" => "0" }
      }
      expect(described_class.from_member_json(member)).to eq("login")
    end

    it "appends discriminator when non-zero" do
      member = {
        "user" => { "username" => "old", "discriminator" => "1234" }
      }
      expect(described_class.from_member_json(member)).to eq("old#1234")
    end
  end

  describe ".from_user_json" do
    it "returns global_name before username" do
      expect(described_class.from_user_json({ "username" => "u", "global_name" => "G", "discriminator" => "0" })).to eq("G")
    end
  end

  describe ".fallback_label" do
    it "uses site username when Discord names are blank" do
      user = create(:user, username: "siteuser", discord_global_name: nil, discord_username: nil)
      expect(described_class.fallback_label(user)).to eq("siteuser")
    end
  end
end
