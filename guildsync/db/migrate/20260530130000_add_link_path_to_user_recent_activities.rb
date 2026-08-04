# frozen_string_literal: true

class AddLinkPathToUserRecentActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :user_recent_activities, :link_path, :string, limit: 2048, null: true
  end
end
