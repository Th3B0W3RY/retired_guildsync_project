class CreateEmailLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :email_logs, if_not_exists: true do |t|
      t.string :to, null: false
      t.string :subject, null: false
      t.string :status, null: false
      t.text :error_message
      t.datetime :sent_at
      t.datetime :opened_at
      t.datetime :clicked_at
      t.integer :retry_count, default: 0
      t.datetime :last_retry_at

      t.timestamps
    end

    add_index :email_logs, :to, if_not_exists: true
    add_index :email_logs, :status, if_not_exists: true
    add_index :email_logs, :sent_at, if_not_exists: true
  end
end
