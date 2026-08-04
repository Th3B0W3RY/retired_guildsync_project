# frozen_string_literal: true

class CreateFeatureRequestVotes < ActiveRecord::Migration[8.0]
  def change
    create_table :feature_request_votes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :feature_request, null: false, foreign_key: true

      t.timestamps
    end

    add_index :feature_request_votes, [ :user_id, :feature_request_id ],
              unique: true,
              name: "index_feature_request_votes_on_user_and_request"
  end
end
