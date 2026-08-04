# frozen_string_literal: true

class CreateContentModerationTables < ActiveRecord::Migration[8.0]
  def change
    create_table :blocked_words do |t|
      t.string :word, null: false
      t.string :category, default: "profanity"
      t.boolean :active, default: true, null: false
      t.integer :times_triggered, default: 0, null: false
      t.timestamps
    end
    add_index :blocked_words, :word, unique: true
    add_index :blocked_words, :active

    create_table :moderation_flags do |t|
      t.string :flaggable_type, null: false
      t.bigint :flaggable_id, null: false
      t.bigint :reported_by_id
      t.string :reason
      t.text :details
      t.string :status, default: "pending", null: false
      t.timestamps
    end
    add_index :moderation_flags, [ :flaggable_type, :flaggable_id ]
    add_index :moderation_flags, :status

    create_table :user_warnings do |t|
      t.bigint :user_id, null: false
      t.bigint :issued_by_id, null: false
      t.string :reason
      t.string :level, default: "warning"
      t.datetime :expires_at
      t.text :notes
      t.timestamps
    end
    add_index :user_warnings, :user_id
    add_index :user_warnings, :issued_by_id
    add_index :user_warnings, :expires_at

    create_table :moderation_audit_logs do |t|
      t.bigint :admin_id
      t.string :admin_email
      t.string :action, null: false
      t.string :content_type
      t.bigint :content_id
      t.text :notes
      t.timestamps
    end
    add_index :moderation_audit_logs, :admin_id
    add_index :moderation_audit_logs, [ :content_type, :content_id ]
    add_index :moderation_audit_logs, :created_at

    create_table :moderation_health_checks do |t|
      t.string :check_id, null: false
      t.boolean :passed, default: true, null: false
      t.integer :warning_count, default: 0, null: false
      t.integer :fail_count, default: 0, null: false
      t.jsonb :details, default: {}
      t.datetime :next_run
      t.timestamps
    end
    add_index :moderation_health_checks, :check_id, unique: true
    add_index :moderation_health_checks, :created_at
    add_index :moderation_health_checks, :passed
  end
end
