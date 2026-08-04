# frozen_string_literal: true

class CreateBackupCodes < ActiveRecord::Migration[7.2]
  def change
    create_table :backup_codes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.string :last_four, null: false
      t.boolean :active, default: true, null: false
      t.boolean :used, default: false, null: false
      t.datetime :used_at
      t.datetime :generated_at, null: false
      t.datetime :invalidated_at
      t.string :invalidated_reason
      t.timestamps
    end

    add_index :backup_codes, [:user_id, :active]
    add_index :backup_codes, :last_four

    create_table :backup_code_usage_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :backup_code, null: true, foreign_key: true
      t.datetime :used_at, null: false
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    add_column :users, :last_backup_generation_at, :datetime
    add_column :users, :last_backup_generation_ip, :string
  end
end
