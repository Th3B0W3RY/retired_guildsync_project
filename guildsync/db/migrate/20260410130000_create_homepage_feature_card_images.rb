# frozen_string_literal: true

class CreateHomepageFeatureCardImages < ActiveRecord::Migration[8.0]
  def change
    create_table :homepage_feature_card_images do |t|
      t.timestamps
    end
  end
end
