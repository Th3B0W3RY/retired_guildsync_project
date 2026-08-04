# frozen_string_literal: true

class BackfillPricingPlanCardFeatures < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:pricing_plans)

    require Rails.root.join("lib/pricing_plan_card_defaults")

    PricingPlanCardDefaults::FEATURES_BY_PLAN_NAME.each do |name, features|
      next if features.blank?

      PricingPlan.where(name: name).find_each do |plan|
        plan.update_column(:features, features)
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
