# frozen_string_literal: true

class CreateLandingUserFeedbacksAndHomepageFeatureCards < ActiveRecord::Migration[8.0]
  def change
    create_table :landing_user_feedbacks do |t|
      t.integer :position, null: false, default: 0
      t.boolean :visible, null: false, default: true

      t.timestamps
    end

    add_index :landing_user_feedbacks, [ :visible, :position ], name: "index_landing_user_feedbacks_on_visible_and_position"

    create_table :homepage_feature_cards do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.text :description, null: false
      t.string :icon_key, null: false
      t.integer :position, null: false, default: 0
      t.boolean :visible, null: false, default: true

      t.timestamps
    end

    add_index :homepage_feature_cards, :slug, unique: true
    add_index :homepage_feature_cards, [ :visible, :position ], name: "index_homepage_feature_cards_on_visible_and_position"
  end
end
