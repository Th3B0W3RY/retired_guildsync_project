class CreatePricingPlans < ActiveRecord::Migration[8.0]
  def change
    create_table :pricing_plans, if_not_exists: true do |t|
      t.string :name, null: false
      t.decimal :price, precision: 10, scale: 2
      t.string :price_display, null: false # e.g., "$0", "$8.99", "Custom-Pricing"
      t.string :period, null: false # e.g., "forever", "per month", "pricing"
      t.text :description
      t.boolean :popular, default: false, null: false
      t.boolean :active, default: true, null: false
      t.integer :max_guilds # null means unlimited
      t.integer :max_members_per_guild # null means unlimited
      t.jsonb :features, default: [], null: false # Array of feature strings
      t.integer :display_order, default: 0, null: false
      t.string :cta_text, default: "Get Started"
      t.string :cta_path, default: "/api/v1/auth/sign_up"

      t.timestamps
    end

    add_index :pricing_plans, :active, if_not_exists: true
    add_index :pricing_plans, :display_order, if_not_exists: true
    add_index :pricing_plans, :name, unique: true, if_not_exists: true
  end
end
