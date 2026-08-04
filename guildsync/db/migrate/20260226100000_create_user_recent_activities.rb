# frozen_string_literal: true

class CreateUserRecentActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :user_recent_activities, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :path, null: false, limit: 2048
      t.string :label, null: false, limit: 500
      t.references :subject, polymorphic: true, null: true

      t.timestamps
    end

    add_index :user_recent_activities, [ :user_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
  end
end
