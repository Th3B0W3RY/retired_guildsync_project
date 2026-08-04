class AddStripeFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :stripe_customer_id, :string, if_not_exists: true
    add_column :users, :stripe_subscription_id, :string, if_not_exists: true
    add_column :users, :plan, :string, if_not_exists: true
    
    add_index :users, :stripe_customer_id, unique: true, where: "stripe_customer_id IS NOT NULL", if_not_exists: true
    add_index :users, :stripe_subscription_id, unique: true, where: "stripe_subscription_id IS NOT NULL", if_not_exists: true
  end
end

