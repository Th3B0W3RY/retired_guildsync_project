class SubscriptionProrationAndWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :first_paid_invoice_at, :datetime
    add_index :subscriptions, :first_paid_invoice_at

    create_table :stripe_webhook_events do |t|
      t.string :stripe_event_id, null: false
      t.string :event_type, null: false
      t.datetime :processed_at

      t.timestamps
    end
    add_index :stripe_webhook_events, :stripe_event_id, unique: true
  end
end
