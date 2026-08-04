class CreateUserComplianceWarnings < ActiveRecord::Migration[8.0]
  def change
    create_table :user_compliance_warnings do |t|
      t.references :user, null: false, foreign_key: true
      t.string :warning_type, null: false
      t.boolean :active, null: false, default: true
      t.text :message, null: false
      t.jsonb :details_json, null: false, default: {}
      t.integer :conflict_count, null: false, default: 0
      t.boolean :locked_by_policy, null: false, default: false
      t.datetime :last_detected_at
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :user_compliance_warnings, [ :user_id, :warning_type ], unique: true, name: "index_ucw_on_user_and_type"
    add_index :user_compliance_warnings, [ :warning_type, :active ], name: "index_ucw_on_type_and_active"
  end
end
