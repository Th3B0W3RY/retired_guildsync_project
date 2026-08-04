# frozen_string_literal: true

class CreateFeatureRequestComments < ActiveRecord::Migration[8.0]
  def change
    create_table :feature_request_comments do |t|
      t.references :feature_request, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :feature_request_comments, [ :feature_request_id, :created_at ]
  end
end
