class AddStripePriceIdToSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :stripe_price_id, :string, if_not_exists: true
  end
end
