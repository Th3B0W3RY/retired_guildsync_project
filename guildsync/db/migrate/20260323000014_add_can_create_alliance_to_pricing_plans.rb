# frozen_string_literal: true

class AddCanCreateAllianceToPricingPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_plans, :can_create_alliance, :boolean, null: false, default: false
  end
end
