# frozen_string_literal: true

class AddAnnualPriceToPricingPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :pricing_plans, :stripe_price_id_annual, :string
    add_column :pricing_plans, :price_display_annual, :string
  end
end
