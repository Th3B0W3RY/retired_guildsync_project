class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :pricing_plan, null: false, foreign_key: true
      t.integer :status, default: 0, null: false # 0: active, 1: canceled, 2: expired, 3: trialing
      t.datetime :started_at, null: false
      t.datetime :expires_at # null means never expires (for free/forever plans)
      t.datetime :canceled_at
      t.string :stripe_subscription_id
      t.string :stripe_customer_id
      t.datetime :trial_ends_at

      t.timestamps
    end

    # Note: user_id index is already created by t.references :user above
    add_index :subscriptions, :status, if_not_exists: true
    add_index :subscriptions, :stripe_subscription_id, unique: true, where: "stripe_subscription_id IS NOT NULL", if_not_exists: true
    add_index :subscriptions, [ :user_id, :status ], if_not_exists: true
  end
end
