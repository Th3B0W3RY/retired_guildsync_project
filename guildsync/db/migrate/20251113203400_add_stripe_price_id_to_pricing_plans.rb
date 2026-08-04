class AddStripePriceIdToPricingPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_plans, :stripe_price_id, :string, if_not_exists: true
  end
end
