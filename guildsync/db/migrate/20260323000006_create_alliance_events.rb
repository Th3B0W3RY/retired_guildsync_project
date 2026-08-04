# frozen_string_literal: true

class CreateAllianceEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_events do |t|
      t.bigint  :alliance_id,    null: false
      t.bigint  :created_by_id,  null: false
      t.string  :title,          null: false
      t.text    :description
      t.datetime :scheduled_at,  null: false
      t.integer :duration
      t.integer :status,         null: false, default: 0  # 0=scheduled, 1=in_progress, 2=completed, 3=cancelled
      t.string  :location
      t.string  :event_type

      t.timestamps
    end

    add_index :alliance_events, :alliance_id
    add_index :alliance_events, :created_by_id
    add_index :alliance_events, :scheduled_at
    add_foreign_key :alliance_events, :alliances
    add_foreign_key :alliance_events, :users, column: :created_by_id
  end
end
