class CreateEventParticipations < ActiveRecord::Migration[8.0]
  def change
    create_table :event_participations, if_not_exists: true do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :status, default: 0, null: false
      t.text :notes

      t.timestamps
    end

    add_index :event_participations, [ :event_id, :user_id ], unique: true, if_not_exists: true
  end
end
