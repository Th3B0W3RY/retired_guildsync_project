# frozen_string_literal: true

class AddDeletedAtToFeatureRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :feature_requests, :deleted_at, :datetime
    add_index :feature_requests, :deleted_at
  end
end
