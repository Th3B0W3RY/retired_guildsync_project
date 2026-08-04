class CreateGearUploadRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :gear_upload_requests, if_not_exists: true do |t|
      t.references :guild, null: false, foreign_key: true
      t.references :requester, null: false, foreign_key: { to_table: :users }
      t.references :target_user, null: false, foreign_key: { to_table: :users }
      t.integer :status, default: 0, null: false
      t.datetime :requested_at, null: false
      t.datetime :completed_at
      t.string :discord_message_id
      t.timestamps
    end

    add_index :gear_upload_requests, [:guild_id, :target_user_id, :status], if_not_exists: true
    add_index :gear_upload_requests, :status, if_not_exists: true
    add_index :gear_upload_requests, :requested_at, if_not_exists: true
  end
end
