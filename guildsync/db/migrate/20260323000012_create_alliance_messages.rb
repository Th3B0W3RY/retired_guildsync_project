# frozen_string_literal: true

class CreateAllianceMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_messages do |t|
      t.bigint  :alliance_id,   null: false
      t.bigint  :sender_id,     null: false
      t.text    :content,       null: false
      t.integer :message_type,  null: false, default: 0  # 0=all_members, 1=gm_only

      t.timestamps
    end

    add_index :alliance_messages, :alliance_id
    add_index :alliance_messages, :sender_id
    add_index :alliance_messages, [ :alliance_id, :message_type ]
    add_index :alliance_messages, :created_at
    add_foreign_key :alliance_messages, :alliances
    add_foreign_key :alliance_messages, :users, column: :sender_id
  end
end
