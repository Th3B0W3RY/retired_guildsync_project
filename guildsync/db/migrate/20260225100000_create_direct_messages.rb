# frozen_string_literal: true

class CreateDirectMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :direct_messages, if_not_exists: true do |t|
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.references :guild, null: true, foreign_key: true
      t.text :content, null: false

      t.timestamps
    end

    add_index :direct_messages, [ :sender_id, :recipient_id, :created_at ], if_not_exists: true
    add_index :direct_messages, [ :recipient_id, :sender_id, :created_at ], if_not_exists: true
  end
end
