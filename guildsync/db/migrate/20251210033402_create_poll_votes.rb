class CreatePollVotes < ActiveRecord::Migration[8.0]
  def change
    create_table :poll_votes, if_not_exists: true do |t|
      t.references :poll, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :choice, null: false

      t.timestamps
    end

    add_index :poll_votes, [ :poll_id, :user_id ], unique: true, if_not_exists: true
  end
end
