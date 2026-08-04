# frozen_string_literal: true

class AddModerationToFeatureRequestsAndComments < ActiveRecord::Migration[8.0]
  def change
    add_column :feature_requests, :moderation_status, :string, default: "approved", null: false
    add_column :feature_requests, :moderation_flagged_at, :datetime
    add_column :feature_requests, :moderation_reviewed_at, :datetime
    add_column :feature_requests, :moderation_reviewed_by_id, :bigint
    add_column :feature_requests, :moderation_reason, :string
    add_column :feature_requests, :moderation_notes, :text
    add_column :feature_requests, :moderation_triggered_words, :text

    add_column :feature_request_comments, :moderation_status, :string, default: "approved", null: false
    add_column :feature_request_comments, :moderation_flagged_at, :datetime
    add_column :feature_request_comments, :moderation_reviewed_at, :datetime
    add_column :feature_request_comments, :moderation_reviewed_by_id, :bigint
    add_column :feature_request_comments, :moderation_reason, :string
    add_column :feature_request_comments, :moderation_notes, :text
    add_column :feature_request_comments, :moderation_triggered_words, :text

    add_index :feature_requests, :moderation_status
    add_index :feature_requests, :moderation_reviewed_by_id
    add_index :feature_request_comments, :moderation_status
    add_index :feature_request_comments, :moderation_reviewed_by_id
  end
end
