class AddDeletedAtIndexesToFeatureRequestComments < ActiveRecord::Migration[8.0]
  def change
    add_index :feature_request_comments, :deleted_at
    add_index :feature_request_comments, [ :feature_request_id, :deleted_at ], name: "idx_feature_request_comments_on_request_and_deleted_at"
  end
end
