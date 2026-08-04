# frozen_string_literal: true

class AddDeletedAtToLandingMarketingCms < ActiveRecord::Migration[8.0]
  def change
    add_column :landing_user_feedbacks, :deleted_at, :datetime
    add_index :landing_user_feedbacks, :deleted_at

    add_column :homepage_feature_cards, :deleted_at, :datetime
    add_index :homepage_feature_cards, :deleted_at
  end
end
