class CreateLoginHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :login_histories, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.text :user_agent
      t.datetime :login_at, null: false
      t.datetime :logout_at

      t.timestamps
    end

    add_index :login_histories, :login_at, if_not_exists: true
  end
end
