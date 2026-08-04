# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanEntitlementService do
  describe ".allowed?" do
    it "returns false when user is nil" do
      expect(described_class.allowed?(nil, :activity_feed)).to be false
    end

    context "with a Free-plan user" do
      let(:user) { create(:user) }

      it "denies activity_feed" do
        expect(described_class.allowed?(user, :activity_feed)).to be false
      end

      it "denies guild_documents" do
        expect(described_class.allowed?(user, :guild_documents)).to be false
      end

      it "denies file_storage" do
        expect(described_class.allowed?(user, :file_storage)).to be false
      end

      it "denies beta_features when the flag is off" do
        user.update!(beta_features_enabled: false)
        expect(described_class.allowed?(user, :beta_features)).to be false
      end

      it "allows beta_features when the user flag is enabled" do
        user.update!(beta_features_enabled: true)
        expect(described_class.allowed?(user, :beta_features)).to be true
      end

      it "accepts string feature names" do
        expect(described_class.allowed?(user, "ACTIVITY_FEED")).to be false
      end
    end

    context "with a Basic-plan user" do
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
      let(:user) do
        u = create(:user)
        u.subscribe_to_plan!(basic_plan)
        u
      end

      it "allows activity_feed" do
        expect(described_class.allowed?(user, :activity_feed)).to be true
      end

      it "allows message_center" do
        expect(described_class.allowed?(user, :message_center)).to be true
      end

      it "denies guild_documents" do
        expect(described_class.allowed?(user, :guild_documents)).to be false
      end

      it "denies file_storage" do
        expect(described_class.allowed?(user, :file_storage)).to be false
      end

      it "denies ai_gear_scanner" do
        expect(described_class.allowed?(user, :ai_gear_scanner)).to be false
      end

      it "allows ai_gear_scanner when the pricing plan row enables it via feature_entitlements" do
        basic_plan.update!(feature_entitlements: { "ai_gear_scanner" => true })
        expect(described_class.allowed?(user, :ai_gear_scanner)).to be true
      end
    end

    context "with an Upgraded-plan user" do
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
      let(:user) do
        u = create(:user)
        u.subscribe_to_plan!(upgraded_plan)
        u
      end

      it "allows guild_documents" do
        expect(described_class.allowed?(user, :guild_documents)).to be true
      end

      it "allows file_storage" do
        expect(described_class.allowed?(user, :file_storage)).to be true
      end

      it "allows ai_gear_scanner" do
        expect(described_class.allowed?(user, :ai_gear_scanner)).to be true
      end
    end

    context "with an Elite-plan user" do
      let(:elite_plan) do
        PricingPlan.where("LOWER(TRIM(name)) = ?", "elite").first ||
          create(:pricing_plan,
            name: "Elite",
            price: 29,
            price_display: "$29",
            period: "per month",
            max_guilds: nil,
            max_members_per_guild: nil,
            active: true,
            display_order: 98)
      end
      let(:user) do
        u = create(:user)
        u.subscribe_to_plan!(elite_plan)
        u
      end

      it "allows beta_features from the plan matrix" do
        user.update!(beta_features_enabled: false)
        expect(described_class.allowed?(user, :beta_features)).to be true
      end

      it "allows ai_gear_scanner from the plan matrix" do
        expect(described_class.allowed?(user, :ai_gear_scanner)).to be true
      end
    end

    context "with a plan name that has no matrix row" do
      let(:orphan_plan) do
        create(:pricing_plan,
          name: "MatrixOrphan #{SecureRandom.hex(4)}",
          price: 1,
          price_display: "$1",
          period: "per month",
          max_guilds: 1,
          max_members_per_guild: 10,
          active: true,
          display_order: 199)
      end
      let(:user) do
        u = create(:user)
        u.subscribe_to_plan!(orphan_plan)
        u
      end

      it "denies features that are not explicitly true in an empty row" do
        expect(described_class.allowed?(user, :polls)).to be false
      end

      it "allows features set on the plan when YAML has no tier row" do
        orphan_plan.update!(feature_entitlements: { "polls" => true, "events" => true })
        expect(described_class.allowed?(user, :polls)).to be true
        expect(described_class.allowed?(user, :events)).to be true
      end
    end
  end
end
