class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :event_type
      t.datetime :scheduled_at, null: false
      t.integer :duration
      t.integer :status, default: 0, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :events, :scheduled_at, if_not_exists: true
  end
end
