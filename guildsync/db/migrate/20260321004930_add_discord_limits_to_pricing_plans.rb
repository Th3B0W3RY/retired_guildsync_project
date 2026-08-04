class AddDiscordLimitsToPricingPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_plans, :max_polls, :integer
    add_column :pricing_plans, :max_loot_rolls, :integer
    add_column :pricing_plans, :max_events, :integer
  end
end
