# frozen_string_literal: true

require "rails_helper"

RSpec.describe PricingPlanInitializer do
  describe ".ensure_plans_exist!" do
    it "sets can_create_alliance on Free vs paid tiers" do
      described_class.ensure_plans_exist!

      expect(PricingPlan.find_by(name: "Free")&.can_create_alliance).to eq(false)
      expect(PricingPlan.find_by(name: "Basic")&.can_create_alliance).to eq(true)
      expect(PricingPlan.find_by(name: "Upgraded")&.can_create_alliance).to eq(true)
      expect(PricingPlan.find_by(name: "Elite")&.can_create_alliance).to eq(true)
    end

    it "does not overwrite marketing features after they were customized" do
      described_class.ensure_plans_exist!
      basic = PricingPlan.find_by!(name: "Basic")
      basic.update_column(:features, [ "Admin-written line" ])

      described_class.ensure_plans_exist!

      expect(basic.reload.features).to eq([ "Admin-written line" ])
    end

    it "still syncs product limits on existing plans" do
      described_class.ensure_plans_exist!
      free = PricingPlan.find_by!(name: "Free")
      free.update_column(:max_members_per_guild, 1)

      described_class.ensure_plans_exist!

      expect(free.reload.max_members_per_guild).to eq(75)
    end
  end
end
