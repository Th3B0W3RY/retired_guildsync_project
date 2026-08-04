# frozen_string_literal: true

class CreateFeatureRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :feature_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description, null: false
      t.string :status, null: false, default: "considering"
      t.integer :vote_count, null: false, default: 0
      t.integer :order, null: false, default: 0
      t.boolean :is_pinned, null: false, default: false
      t.text :admin_notes
      t.string :release_note_url

      t.timestamps
    end

    add_index :feature_requests, :status
    add_index :feature_requests, [ :status, :is_pinned ], name: "index_feature_requests_on_status_and_pinned"
  end
end
