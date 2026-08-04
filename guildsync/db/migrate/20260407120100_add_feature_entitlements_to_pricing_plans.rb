# frozen_string_literal: true

class AddFeatureEntitlementsToPricingPlans < ActiveRecord::Migration[8.0]
  def up
    add_column :pricing_plans, :feature_entitlements, :jsonb, default: {}, null: false

    path = Rails.root.join("config/plan_entitlements.yml")
    return unless File.exist?(path)

    matrix = YAML.load_file(path).transform_keys { |k| k.to_s.downcase.strip }
    PricingPlan.reset_column_information
    PricingPlan.find_each do |plan|
      key = plan.name.to_s.downcase.strip
      row = matrix[key]
      next if row.blank?

      plan.update_columns(feature_entitlements: row.stringify_keys, updated_at: Time.current)
    end
  end

  def down
    remove_column :pricing_plans, :feature_entitlements
  end
end
