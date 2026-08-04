# frozen_string_literal: true

class BackfillCanCreateAllianceOnPaidPlans < ActiveRecord::Migration[8.0]
  # Paid tiers (and legacy Standard) may have can_create_alliance left at DB default false
  # after adding the column; trialing subscriptions still use these plans.
  PAID_PLAN_NAMES = %w[Basic Upgraded Elite Standard].freeze

  def up
    return unless table_exists?(:pricing_plans)

    paid = PAID_PLAN_NAMES.map(&:downcase)
    PricingPlan.where("LOWER(name) IN (?)", paid).update_all(can_create_alliance: true)
    PricingPlan.where("LOWER(name) = ?", "free").update_all(can_create_alliance: false)
  end

  def down
    return unless table_exists?(:pricing_plans)

    PricingPlan.update_all(can_create_alliance: false)
  end
end
