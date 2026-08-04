class CreatePolls < ActiveRecord::Migration[8.0]
  def change
    create_table :polls, if_not_exists: true do |t|
      t.string :title
      t.text :description
      t.datetime :deadline
      t.boolean :anonymous
      t.references :guild, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :discord_message_id
      t.string :discord_channel_id

      t.timestamps
    end
  end
end
