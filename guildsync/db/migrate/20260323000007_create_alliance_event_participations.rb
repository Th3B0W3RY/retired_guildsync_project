# frozen_string_literal: true

class CreateAllianceEventParticipations < ActiveRecord::Migration[8.0]
  def change
    create_table :alliance_event_participations do |t|
      t.bigint  :alliance_event_id, null: false
      t.bigint  :user_id,           null: false
      t.integer :status,            null: false, default: 0  # 0=attending, 1=maybe, 2=declined

      t.timestamps
    end

    add_index :alliance_event_participations, :alliance_event_id
    add_index :alliance_event_participations, :user_id
    add_index :alliance_event_participations, [ :alliance_event_id, :user_id ], unique: true
    add_foreign_key :alliance_event_participations, :alliance_events
    add_foreign_key :alliance_event_participations, :users
  end
end
