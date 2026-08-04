# frozen_string_literal: true

require "rails_helper"

RSpec.describe PricingPlan, type: :model do
  let!(:free_plan) do
    create(:pricing_plan,
           name: "Free",
           price: 0,
           price_display: "$0",
           period: "forever",
           max_guilds: 1,
           max_members_per_guild: 10,
           active: true,
           display_order: 1)
  end

  let!(:pro_plan) do
    create(:pricing_plan,
           name: "Pro",
           price: 9.99,
           price_display: "$9.99",
           period: "month",
           max_guilds: 5,
           max_members_per_guild: 50,
           active: true,
           display_order: 2)
  end

  describe "#free_tier?" do
    it "is true when name is Free (case-insensitive)" do
      expect(build(:pricing_plan, name: "Free").free_tier?).to be true
      expect(build(:pricing_plan, name: "free").free_tier?).to be true
      expect(build(:pricing_plan, name: "Basic").free_tier?).to be false
    end
  end

  describe ".paid_tiers" do
    it "excludes the Free plan by name" do
      expect(PricingPlan.paid_tiers).not_to include(free_plan)
      expect(PricingPlan.paid_tiers).to include(pro_plan)
    end
  end

  describe "scopes" do
    it "filters active plans" do
      inactive_plan = create(:pricing_plan, active: false)

      active_plans = PricingPlan.active
      expect(active_plans).to include(free_plan)
      expect(active_plans).to include(pro_plan)
      expect(active_plans).not_to include(inactive_plan)
    end

    it "orders plans by display_order" do
      ordered = PricingPlan.ordered
      expect(ordered.first.display_order).to be <= ordered.second.display_order
    end
  end

  describe ".find_by_stripe_price" do
    let!(:plan_monthly) do
      create(:pricing_plan, name: "Basic", stripe_price_id: "price_monthly_123", stripe_price_id_annual: "price_annual_123")
    end

    it "returns plan when price_id matches stripe_price_id" do
      expect(PricingPlan.find_by_stripe_price("price_monthly_123")).to eq(plan_monthly)
    end

    it "returns plan when price_id matches stripe_price_id_annual" do
      expect(PricingPlan.find_by_stripe_price("price_annual_123")).to eq(plan_monthly)
    end

    it "returns nil for unknown price_id" do
      expect(PricingPlan.find_by_stripe_price("price_unknown")).to be_nil
    end

    it "returns nil for blank price_id" do
      expect(PricingPlan.find_by_stripe_price("")).to be_nil
      expect(PricingPlan.find_by_stripe_price(nil)).to be_nil
    end
  end

  describe ".find_by_effective_stripe_price" do
    it "returns plan when price_id matches DB stripe_price_id" do
      plan = create(:pricing_plan, name: "Basic", stripe_price_id: "price_db_month", stripe_price_id_annual: "price_db_year")
      expect(PricingPlan.find_by_effective_stripe_price("price_db_month")).to eq(plan)
    end

    it "returns plan when price_id matches DB stripe_price_id_annual" do
      plan = create(:pricing_plan, name: "Basic", stripe_price_id: "price_db_month", stripe_price_id_annual: "price_db_year")
      expect(PricingPlan.find_by_effective_stripe_price("price_db_year")).to eq(plan)
    end

    it "returns plan when price_id matches ENV fallback (effective_stripe_price_id)" do
      plan = create(:pricing_plan, name: "Basic", stripe_price_id: nil, stripe_price_id_annual: nil, active: true)
      env_key = "STRIPE_BASIC_PRICE_ID"
      original = ENV[env_key]
      ENV[env_key] = "price_env_basic_month"
      expect(PricingPlan.find_by_effective_stripe_price("price_env_basic_month")).to eq(plan)
    ensure
      ENV[env_key] = original
    end

    it "returns plan when price_id matches ENV fallback (effective_stripe_price_id_annual)" do
      plan = create(:pricing_plan, name: "Basic", stripe_price_id: nil, stripe_price_id_annual: nil, active: true)
      env_key = "STRIPE_BASIC_PRICE_ID_ANNUAL"
      original = ENV[env_key]
      ENV[env_key] = "price_env_basic_annual"
      expect(PricingPlan.find_by_effective_stripe_price("price_env_basic_annual")).to eq(plan)
    ensure
      ENV[env_key] = original
    end

    it "returns nil for unknown price_id" do
      create(:pricing_plan, name: "Basic", stripe_price_id: "price_other", stripe_price_id_annual: nil)
      expect(PricingPlan.find_by_effective_stripe_price("price_unknown")).to be_nil
    end

    it "returns nil for blank price_id" do
      expect(PricingPlan.find_by_effective_stripe_price("")).to be_nil
      expect(PricingPlan.find_by_effective_stripe_price(nil)).to be_nil
    end
  end

  describe "#price_id_for_interval" do
    let(:plan) do
      create(:pricing_plan, stripe_price_id: "price_mo", stripe_price_id_annual: "price_yr")
    end

    it "returns annual price id for year interval" do
      expect(plan.price_id_for_interval("year")).to eq("price_yr")
      expect(plan.price_id_for_interval(:year)).to eq("price_yr")
    end

    it "returns monthly price id for month or other" do
      expect(plan.price_id_for_interval("month")).to eq("price_mo")
      expect(plan.price_id_for_interval(:month)).to eq("price_mo")
      expect(plan.price_id_for_interval("")).to eq("price_mo")
    end
  end

  describe "#formatted_price_annual" do
    it "returns price_display_annual when set" do
      plan = create(:pricing_plan, price_display: "$10", price_display_annual: "$108")
      expect(plan.formatted_price_annual).to eq("$108")
    end

    it "falls back to price_display when price_display_annual blank" do
      plan = create(:pricing_plan, price_display: "$10", price_display_annual: nil)
      expect(plan.formatted_price_annual).to eq("$10")
    end
  end
end

