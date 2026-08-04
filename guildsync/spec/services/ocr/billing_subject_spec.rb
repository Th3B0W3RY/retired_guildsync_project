# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ocr::BillingSubject do
  let(:basic_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "basic").first ||
      create(:pricing_plan,
        name: "Basic",
        price: 9,
        price_display: "$9",
        period: "per month",
        max_guilds: 5,
        max_members_per_guild: 100,
        active: true,
        display_order: 91)
  end

  let(:upgraded_plan) do
    PricingPlan.where("LOWER(TRIM(name)) = ?", "upgraded").first ||
      create(:pricing_plan,
        name: "Upgraded",
        price: 16,
        price_display: "$16",
        period: "per month",
        max_guilds: nil,
        max_members_per_guild: nil,
        active: true,
        display_order: 97)
  end

  let(:owner) { create(:user, :discord_auth, skip_free_plan_subscription: true) }
  let(:member) { create(:user, :discord_auth, skip_free_plan_subscription: true) }

  describe ".for_gear_upload" do
    it "returns the actor when guild is nil" do
      expect(described_class.for_gear_upload(actor: member, guild: nil)).to eq(member)
    end

    it "returns nil when actor is nil" do
      guild = create(:guild, owner: owner)
      expect(described_class.for_gear_upload(actor: nil, guild: guild)).to be_nil
    end

    context "with an upgraded owner and guild (no Test Plan from factory)" do
      let!(:guild) do
        owner.subscribe_to_plan!(upgraded_plan)
        create(:guild, owner: owner)
      end

      it "returns the actor when the user is not an active guild member" do
        expect(described_class.for_gear_upload(actor: member, guild: guild)).to eq(member)
      end

      it "returns the guild owner when the owner has the entitlement and the actor is an active member" do
        create(:guild_member, guild: guild, user: member, status: :active)
        expect(described_class.for_gear_upload(actor: member, guild: guild)).to eq(owner)
      end

      it "returns the owner when the actor is the owner (same pool)" do
        expect(described_class.for_gear_upload(actor: owner, guild: guild)).to eq(owner)
      end
    end

    it "returns the actor when the guild owner does not have the stat scanner entitlement" do
      owner.subscribe_to_plan!(basic_plan)
      guild = create(:guild, owner: owner)
      create(:guild_member, guild: guild, user: member, status: :active)
      expect(described_class.for_gear_upload(actor: member, guild: guild)).to eq(member)
    end
  end
end
