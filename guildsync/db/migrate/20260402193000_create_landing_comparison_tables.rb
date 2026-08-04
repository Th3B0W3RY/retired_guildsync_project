# frozen_string_literal: true

class CreateLandingComparisonTables < ActiveRecord::Migration[8.0]
  def up
    create_table :landing_comparison_tables do |t|
      t.integer :position, null: false
      t.string :feature_column_label, null: false, default: "Feature"
      t.string :guildsync_column_label, null: false, default: "GuildSync"
      t.string :competitor_column_label, null: false
      t.boolean :show_guildsync_badge, null: false, default: true
      t.timestamps
    end
    add_index :landing_comparison_tables, :position, unique: true

    create_table :landing_comparison_rows do |t|
      t.references :landing_comparison_table, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :feature_label, null: false
      t.boolean :guildsync_included, null: false, default: true
      t.boolean :competitor_included, null: false, default: false
      t.timestamps
    end
    add_index :landing_comparison_rows, [ :landing_comparison_table_id, :position ], unique: true, name: "idx_landing_compare_rows_on_table_and_position"

    LandingCompare::SeedDefaults.seed!
  end

  def down
    drop_table :landing_comparison_rows, if_exists: true
    drop_table :landing_comparison_tables, if_exists: true
  end
end
