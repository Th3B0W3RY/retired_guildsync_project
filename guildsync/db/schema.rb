# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_30_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "abuse_flags", force: :cascade do |t|
    t.string "target_type", null: false
    t.string "target_value", null: false
    t.string "reason", null: false
    t.integer "severity", default: 1, null: false
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_abuse_flags_on_created_at"
    t.index ["target_type", "target_value"], name: "index_abuse_flags_on_target_type_and_target_value"
  end

  create_table "account_deletion_requests", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "code_digest"
    t.datetime "expires_at"
    t.datetime "sent_at"
    t.datetime "consumed_at"
    t.integer "attempts_count", default: 0, null: false
    t.string "last_sent_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_account_deletion_requests_on_user_id", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_audit_logs", force: :cascade do |t|
    t.string "admin_email", null: false
    t.string "action", null: false
    t.string "controller", null: false
    t.string "record_type"
    t.bigint "record_id"
    t.text "changes_data"
    t.string "ip_address"
    t.text "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_email"], name: "index_admin_audit_logs_on_admin_email"
    t.index ["created_at"], name: "index_admin_audit_logs_on_created_at"
    t.index ["record_type", "record_id"], name: "index_admin_audit_logs_on_record_type_and_record_id"
  end

  create_table "alliance_activity_logs", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "user_id"
    t.bigint "guild_id"
    t.string "action_type", null: false
    t.string "description", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_id", "action_type"], name: "index_alliance_activity_logs_on_alliance_id_and_action_type"
    t.index ["alliance_id", "created_at"], name: "index_alliance_activity_logs_on_alliance_id_and_created_at", order: { created_at: :desc }
    t.index ["alliance_id"], name: "index_alliance_activity_logs_on_alliance_id"
    t.index ["guild_id"], name: "index_alliance_activity_logs_on_guild_id"
    t.index ["user_id"], name: "index_alliance_activity_logs_on_user_id"
  end

  create_table "alliance_disband_votes", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "user_id", null: false
    t.bigint "guild_id", null: false
    t.boolean "vote", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_id", "guild_id"], name: "index_alliance_disband_votes_on_alliance_id_and_guild_id", unique: true
    t.index ["alliance_id"], name: "index_alliance_disband_votes_on_alliance_id"
  end

  create_table "alliance_event_discord_messages", force: :cascade do |t|
    t.bigint "alliance_event_id", null: false
    t.bigint "guild_id", null: false
    t.string "channel_id", null: false
    t.string "discord_message_id", null: false
    t.datetime "posted_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_scheduled_event_id"
    t.index ["alliance_event_id", "guild_id"], name: "idx_alliance_event_discord_messages_event_guild", unique: true
    t.index ["alliance_event_id"], name: "index_alliance_event_discord_messages_on_alliance_event_id"
    t.index ["guild_id"], name: "index_alliance_event_discord_messages_on_guild_id"
  end

  create_table "alliance_event_discord_signups", force: :cascade do |t|
    t.bigint "alliance_event_id", null: false
    t.string "discord_user_id", null: false
    t.string "discord_username"
    t.string "discord_display_name"
    t.integer "role", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_event_id", "discord_user_id"], name: "idx_alliance_event_discord_signups_event_user", unique: true
    t.index ["alliance_event_id"], name: "index_alliance_event_discord_signups_on_alliance_event_id"
  end

  create_table "alliance_event_participations", force: :cascade do |t|
    t.bigint "alliance_event_id", null: false
    t.bigint "user_id"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_user_id"
    t.string "discord_username"
    t.index ["alliance_event_id", "discord_user_id"], name: "idx_alliance_event_parts_event_discord", unique: true, where: "(discord_user_id IS NOT NULL)"
    t.index ["alliance_event_id", "user_id"], name: "idx_alliance_event_parts_event_user", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["alliance_event_id"], name: "index_alliance_event_participations_on_alliance_event_id"
    t.index ["user_id"], name: "index_alliance_event_participations_on_user_id"
  end

  create_table "alliance_events", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "created_by_id", null: false
    t.string "title", null: false
    t.text "description"
    t.datetime "scheduled_at", null: false
    t.integer "duration"
    t.integer "status", default: 0, null: false
    t.string "location"
    t.string "event_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "max_participants"
    t.string "squad_leader"
    t.jsonb "discord_role_mentions", default: []
    t.jsonb "role_categories", default: ["dps", "tank", "healer", "ranged"]
    t.datetime "deleted_at"
    t.index ["alliance_id"], name: "index_alliance_events_on_alliance_id"
    t.index ["created_by_id"], name: "index_alliance_events_on_created_by_id"
    t.index ["deleted_at"], name: "index_alliance_events_on_deleted_at"
    t.index ["scheduled_at"], name: "index_alliance_events_on_scheduled_at"
  end

  create_table "alliance_guilds", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "guild_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "invited_by_user_id"
    t.datetime "joined_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_id", "guild_id"], name: "index_alliance_guilds_on_alliance_id_and_guild_id", unique: true
    t.index ["alliance_id"], name: "index_alliance_guilds_on_alliance_id"
    t.index ["guild_id"], name: "index_alliance_guilds_on_guild_id"
    t.index ["guild_id"], name: "index_alliance_guilds_on_guild_id_active_unique", unique: true, where: "(status = 0)"
  end

  create_table "alliance_invites", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "guild_id", null: false
    t.bigint "invited_by_user_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_id", "guild_id", "status"], name: "index_alliance_invites_on_alliance_id_and_guild_id_and_status"
    t.index ["alliance_id"], name: "index_alliance_invites_on_alliance_id"
    t.index ["guild_id"], name: "index_alliance_invites_on_guild_id"
  end

  create_table "alliance_join_requests", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "requesting_guild_id", null: false
    t.bigint "requested_by_user_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_id", "requesting_guild_id"], name: "index_alliance_join_requests_pending_unique", unique: true, where: "(status = 0)"
    t.index ["alliance_id"], name: "index_alliance_join_requests_on_alliance_id"
    t.index ["requested_by_user_id"], name: "index_alliance_join_requests_on_requested_by_user_id"
    t.index ["requesting_guild_id"], name: "index_alliance_join_requests_on_requesting_guild_id"
  end

  create_table "alliance_loot_roll_discord_messages", force: :cascade do |t|
    t.bigint "alliance_loot_roll_id", null: false
    t.bigint "guild_id", null: false
    t.string "channel_id", null: false
    t.string "discord_message_id", null: false
    t.datetime "posted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_loot_roll_id", "guild_id"], name: "idx_alliance_loot_roll_discord_messages_roll_guild", unique: true
    t.index ["alliance_loot_roll_id"], name: "idx_on_alliance_loot_roll_id_df33f41fcb"
    t.index ["guild_id"], name: "index_alliance_loot_roll_discord_messages_on_guild_id"
  end

  create_table "alliance_loot_roll_entries", force: :cascade do |t|
    t.bigint "alliance_loot_roll_id", null: false
    t.bigint "user_id"
    t.integer "roll_value"
    t.string "display_name"
    t.boolean "is_reroll", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_user_id"
    t.string "discord_username"
    t.index ["alliance_loot_roll_id", "discord_user_id"], name: "idx_alliance_loot_entries_roll_discord", unique: true, where: "(discord_user_id IS NOT NULL)"
    t.index ["alliance_loot_roll_id", "user_id"], name: "idx_alliance_loot_entries_roll_user", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["alliance_loot_roll_id"], name: "index_alliance_loot_roll_entries_on_alliance_loot_roll_id"
    t.index ["user_id"], name: "index_alliance_loot_roll_entries_on_user_id"
  end

  create_table "alliance_loot_rolls", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "creator_id", null: false
    t.bigint "winner_entry_id"
    t.string "title", null: false
    t.text "description"
    t.integer "min_roll", default: 1, null: false
    t.integer "max_roll", default: 100, null: false
    t.boolean "anonymous", default: false, null: false
    t.datetime "deadline_at"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["alliance_id"], name: "index_alliance_loot_rolls_on_alliance_id"
    t.index ["creator_id"], name: "index_alliance_loot_rolls_on_creator_id"
    t.index ["deleted_at"], name: "index_alliance_loot_rolls_on_deleted_at"
    t.index ["status"], name: "index_alliance_loot_rolls_on_status"
  end

  create_table "alliance_member_tags", force: :cascade do |t|
    t.bigint "alliance_member_id", null: false
    t.bigint "alliance_tag_id", null: false
    t.bigint "assigned_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_member_id", "alliance_tag_id"], name: "idx_on_alliance_member_id_alliance_tag_id_9023e11d72", unique: true
    t.index ["alliance_member_id"], name: "index_alliance_member_tags_on_alliance_member_id"
    t.index ["alliance_tag_id"], name: "index_alliance_member_tags_on_alliance_tag_id"
    t.index ["assigned_by_id"], name: "index_alliance_member_tags_on_assigned_by_id"
  end

  create_table "alliance_members", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "user_id", null: false
    t.bigint "guild_id", null: false
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_id", "user_id"], name: "index_alliance_members_on_alliance_id_and_user_id", unique: true
    t.index ["alliance_id"], name: "index_alliance_members_on_alliance_id"
    t.index ["guild_id"], name: "index_alliance_members_on_guild_id"
    t.index ["user_id"], name: "index_alliance_members_on_user_id"
  end

  create_table "alliance_messages", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "sender_id", null: false
    t.text "content", null: false
    t.integer "message_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_id", "message_type"], name: "index_alliance_messages_on_alliance_id_and_message_type"
    t.index ["alliance_id"], name: "index_alliance_messages_on_alliance_id"
    t.index ["created_at"], name: "index_alliance_messages_on_created_at"
    t.index ["sender_id"], name: "index_alliance_messages_on_sender_id"
  end

  create_table "alliance_poll_discord_messages", force: :cascade do |t|
    t.bigint "alliance_poll_id", null: false
    t.bigint "guild_id", null: false
    t.string "channel_id", null: false
    t.string "discord_message_id", null: false
    t.datetime "posted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_poll_id", "guild_id"], name: "idx_alliance_poll_discord_messages_poll_guild", unique: true
    t.index ["alliance_poll_id"], name: "index_alliance_poll_discord_messages_on_alliance_poll_id"
    t.index ["guild_id"], name: "index_alliance_poll_discord_messages_on_guild_id"
  end

  create_table "alliance_poll_votes", force: :cascade do |t|
    t.bigint "alliance_poll_id", null: false
    t.bigint "user_id"
    t.integer "choice", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_user_id"
    t.string "discord_username"
    t.index ["alliance_poll_id", "discord_user_id"], name: "idx_alliance_poll_votes_poll_discord", unique: true, where: "(discord_user_id IS NOT NULL)"
    t.index ["alliance_poll_id", "user_id"], name: "idx_alliance_poll_votes_poll_user", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["alliance_poll_id"], name: "index_alliance_poll_votes_on_alliance_poll_id"
    t.index ["user_id"], name: "index_alliance_poll_votes_on_user_id"
  end

  create_table "alliance_polls", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.bigint "creator_id", null: false
    t.string "title", null: false
    t.text "description"
    t.datetime "deadline", null: false
    t.boolean "anonymous", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["alliance_id"], name: "index_alliance_polls_on_alliance_id"
    t.index ["creator_id"], name: "index_alliance_polls_on_creator_id"
    t.index ["deadline"], name: "index_alliance_polls_on_deadline"
    t.index ["deleted_at"], name: "index_alliance_polls_on_deleted_at"
  end

  create_table "alliance_tags", force: :cascade do |t|
    t.bigint "alliance_id", null: false
    t.string "name", null: false
    t.string "color", default: "#6366f1", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alliance_id", "name"], name: "index_alliance_tags_on_alliance_id_and_name", unique: true
    t.index ["alliance_id"], name: "index_alliance_tags_on_alliance_id"
    t.index ["created_by_id"], name: "index_alliance_tags_on_created_by_id"
  end

  create_table "alliances", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.bigint "leader_guild_id", null: false
    t.bigint "leader_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "chat_discord_channel_id"
    t.index ["leader_guild_id"], name: "index_alliances_on_leader_guild_id"
    t.index ["leader_user_id"], name: "index_alliances_on_leader_user_id"
    t.index ["status"], name: "index_alliances_on_status"
  end

  create_table "backup_code_usage_logs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "backup_code_id"
    t.datetime "used_at", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["backup_code_id"], name: "index_backup_code_usage_logs_on_backup_code_id"
    t.index ["user_id"], name: "index_backup_code_usage_logs_on_user_id"
  end

  create_table "backup_codes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "code_digest", null: false
    t.string "last_four", null: false
    t.boolean "active", default: true, null: false
    t.boolean "used", default: false, null: false
    t.datetime "used_at"
    t.datetime "generated_at", null: false
    t.datetime "invalidated_at"
    t.string "invalidated_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_four"], name: "index_backup_codes_on_last_four"
    t.index ["user_id", "active"], name: "index_backup_codes_on_user_id_and_active"
    t.index ["user_id"], name: "index_backup_codes_on_user_id"
  end

  create_table "blocked_words", force: :cascade do |t|
    t.string "word", null: false
    t.string "category", default: "profanity"
    t.boolean "active", default: true, null: false
    t.integer "times_triggered", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source"
    t.datetime "last_seen_at"
    t.datetime "deactivated_at"
    t.index ["active"], name: "index_blocked_words_on_active"
    t.index ["word"], name: "index_blocked_words_on_word", unique: true
  end

  create_table "direct_messages", force: :cascade do |t|
    t.bigint "sender_id", null: false
    t.bigint "recipient_id", null: false
    t.bigint "guild_id"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_direct_messages_on_guild_id"
    t.index ["recipient_id", "sender_id", "created_at"], name: "idx_on_recipient_id_sender_id_created_at_189a936771"
    t.index ["recipient_id"], name: "index_direct_messages_on_recipient_id"
    t.index ["sender_id", "recipient_id", "created_at"], name: "idx_on_sender_id_recipient_id_created_at_9bb8ecd51e"
    t.index ["sender_id"], name: "index_direct_messages_on_sender_id"
  end

  create_table "discord_command_executions", force: :cascade do |t|
    t.string "interaction_token", null: false
    t.string "command_key", null: false
    t.string "status", default: "pending", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["interaction_token", "command_key"], name: "idx_discord_cmd_exec_idempotency", unique: true
  end

  create_table "discord_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "discord_user_id", null: false
    t.string "discord_username"
    t.text "access_token", null: false
    t.text "refresh_token"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "guild_id", null: false
    t.index ["discord_user_id"], name: "index_discord_connections_on_discord_user_id"
    t.index ["guild_id"], name: "index_discord_connections_on_guild_id", unique: true
    t.index ["user_id"], name: "index_discord_connections_on_user_id"
  end

  create_table "discord_event_participations", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.string "discord_user_id", null: false
    t.string "discord_username"
    t.string "discord_message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "on_time", default: false, null: false
    t.index ["event_id", "discord_user_id"], name: "index_discord_event_participations_unique", unique: true
    t.index ["event_id"], name: "index_discord_event_participations_on_event_id"
  end

  create_table "discord_event_signups", force: :cascade do |t|
    t.bigint "discord_event_id", null: false
    t.string "discord_user_id", null: false
    t.string "discord_username"
    t.integer "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0, null: false
    t.string "discord_display_name"
    t.index ["discord_event_id", "discord_user_id"], name: "index_discord_event_signups_unique_user_event", unique: true
    t.index ["discord_event_id"], name: "index_discord_event_signups_on_discord_event_id"
    t.index ["discord_user_id"], name: "index_discord_event_signups_on_discord_user_id"
  end

  create_table "discord_events", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "discord_connection_id", null: false
    t.string "discord_event_id", null: false
    t.string "discord_message_id"
    t.string "channel_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "event_type"
    t.datetime "scheduled_at", null: false
    t.integer "max_participants"
    t.jsonb "role_categories", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "timezone", default: "UTC", null: false
    t.string "squad_leader"
    t.string "location"
    t.json "discord_role_mentions"
    t.datetime "deleted_at"
    t.index ["channel_id"], name: "index_discord_events_on_channel_id"
    t.index ["deleted_at"], name: "index_discord_events_on_deleted_at"
    t.index ["discord_connection_id"], name: "index_discord_events_on_discord_connection_id"
    t.index ["discord_event_id"], name: "index_discord_events_on_discord_event_id", unique: true
    t.index ["discord_message_id"], name: "index_discord_events_on_discord_message_id"
    t.index ["guild_id"], name: "index_discord_events_on_guild_id"
  end

  create_table "discord_onboarding_dms", force: :cascade do |t|
    t.string "discord_user_id", null: false
    t.string "context_type", null: false
    t.bigint "context_id", null: false
    t.datetime "sent_at", null: false
    t.boolean "delivered", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discord_user_id", "context_type", "context_id"], name: "idx_discord_onboarding_dms_unique", unique: true
  end

  create_table "discord_role_syncs", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.string "role_id", null: false
    t.string "role_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id", "role_id"], name: "index_discord_role_syncs_on_guild_id_and_role_id", unique: true
    t.index ["guild_id"], name: "index_discord_role_syncs_on_guild_id"
  end

  create_table "email_logs", force: :cascade do |t|
    t.string "to", null: false
    t.string "subject", null: false
    t.string "status", null: false
    t.text "error_message"
    t.datetime "sent_at"
    t.datetime "opened_at"
    t.datetime "clicked_at"
    t.integer "retry_count", default: 0
    t.datetime "last_retry_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sent_at"], name: "index_email_logs_on_sent_at"
    t.index ["status"], name: "index_email_logs_on_status"
    t.index ["to"], name: "index_email_logs_on_to"
  end

  create_table "error_batch_reports", force: :cascade do |t|
    t.datetime "period_start", null: false
    t.datetime "period_end", null: false
    t.integer "total_errors", default: 0, null: false
    t.integer "unique_clusters", default: 0, null: false
    t.jsonb "report_data", default: {}, null: false
    t.datetime "delivered_at"
    t.string "triggered_by", default: "scheduled", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_error_batch_reports_on_created_at"
    t.index ["period_end"], name: "index_error_batch_reports_on_period_end"
  end

  create_table "error_logs", force: :cascade do |t|
    t.string "error_class", null: false
    t.text "message", null: false
    t.text "backtrace"
    t.jsonb "context"
    t.datetime "occurred_at", null: false
    t.datetime "resolved_at"
    t.string "resolved_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "severity", default: "medium", null: false
    t.text "cause"
    t.index ["occurred_at"], name: "index_error_logs_on_occurred_at"
    t.index ["resolved_at"], name: "index_error_logs_on_resolved_at"
    t.index ["severity"], name: "index_error_logs_on_severity"
  end

  create_table "event_participations", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "user_id"
    t.integer "status", default: 0, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_user_id"
    t.string "discord_username"
    t.index ["event_id", "discord_user_id"], name: "index_event_participations_on_event_discord", unique: true, where: "(discord_user_id IS NOT NULL)"
    t.index ["event_id", "user_id"], name: "index_event_participations_on_event_id_and_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["event_id"], name: "index_event_participations_on_event_id"
    t.index ["user_id"], name: "index_event_participations_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "event_type"
    t.datetime "scheduled_at", null: false
    t.integer "duration"
    t.integer "status", default: 0, null: false
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_event_id"
    t.string "discord_message_id"
    t.string "squad_leader"
    t.string "location"
    t.datetime "deleted_at"
    t.index ["created_by_id"], name: "index_events_on_created_by_id"
    t.index ["deleted_at"], name: "index_events_on_deleted_at"
    t.index ["discord_event_id"], name: "index_events_on_discord_event_id"
    t.index ["discord_message_id"], name: "index_events_on_discord_message_id"
    t.index ["guild_id"], name: "index_events_on_guild_id"
    t.index ["scheduled_at"], name: "index_events_on_scheduled_at"
  end

  create_table "feature_flags", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "enabled", default: false, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_feature_flags_on_name", unique: true
  end

  create_table "feature_request_comments", force: :cascade do |t|
    t.bigint "feature_request_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "moderation_status", default: "approved", null: false
    t.datetime "moderation_flagged_at"
    t.datetime "moderation_reviewed_at"
    t.bigint "moderation_reviewed_by_id"
    t.string "moderation_reason"
    t.text "moderation_notes"
    t.text "moderation_triggered_words"
    t.index ["deleted_at"], name: "index_feature_request_comments_on_deleted_at"
    t.index ["feature_request_id", "created_at"], name: "idx_on_feature_request_id_created_at_2f0e7940ec"
    t.index ["feature_request_id", "deleted_at"], name: "idx_feature_request_comments_on_request_and_deleted_at"
    t.index ["feature_request_id"], name: "index_feature_request_comments_on_feature_request_id"
    t.index ["moderation_reviewed_by_id"], name: "index_feature_request_comments_on_moderation_reviewed_by_id"
    t.index ["moderation_status"], name: "index_feature_request_comments_on_moderation_status"
    t.index ["user_id"], name: "index_feature_request_comments_on_user_id"
  end

  create_table "feature_request_votes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "feature_request_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_request_id"], name: "index_feature_request_votes_on_feature_request_id"
    t.index ["user_id", "feature_request_id"], name: "index_feature_request_votes_on_user_and_request", unique: true
    t.index ["user_id"], name: "index_feature_request_votes_on_user_id"
  end

  create_table "feature_requests", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "status", default: "considering", null: false
    t.integer "vote_count", default: 0, null: false
    t.integer "order", default: 0, null: false
    t.boolean "is_pinned", default: false, null: false
    t.text "admin_notes"
    t.string "release_note_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "moderation_status", default: "approved", null: false
    t.datetime "moderation_flagged_at"
    t.datetime "moderation_reviewed_at"
    t.bigint "moderation_reviewed_by_id"
    t.string "moderation_reason"
    t.text "moderation_notes"
    t.text "moderation_triggered_words"
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_feature_requests_on_deleted_at"
    t.index ["moderation_reviewed_by_id"], name: "index_feature_requests_on_moderation_reviewed_by_id"
    t.index ["moderation_status"], name: "index_feature_requests_on_moderation_status"
    t.index ["status", "is_pinned"], name: "index_feature_requests_on_status_and_pinned"
    t.index ["status"], name: "index_feature_requests_on_status"
    t.index ["user_id"], name: "index_feature_requests_on_user_id"
  end

  create_table "file_entries", force: :cascade do |t|
    t.string "name", null: false
    t.string "content_type"
    t.integer "size"
    t.boolean "compressed", default: false
    t.bigint "guild_id", null: false
    t.bigint "folder_id"
    t.integer "uploaded_by", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_file_entries_on_deleted_at"
    t.index ["folder_id"], name: "index_file_entries_on_folder_id"
    t.index ["guild_id"], name: "index_file_entries_on_guild_id"
    t.index ["uploaded_by"], name: "index_file_entries_on_uploaded_by"
  end

  create_table "folders", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "guild_id", null: false
    t.bigint "parent_folder_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_folders_on_deleted_at"
    t.index ["guild_id"], name: "index_folders_on_guild_id"
    t.index ["parent_folder_id"], name: "index_folders_on_parent_folder_id"
  end

  create_table "fontawesome_free_icons", force: :cascade do |t|
    t.string "style", null: false
    t.string "icon_name", null: false
    t.string "label", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["label"], name: "index_fontawesome_free_icons_on_label"
    t.index ["style", "icon_name"], name: "index_fontawesome_free_icons_on_style_and_icon_name", unique: true
  end

  create_table "games", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.jsonb "ocr_config", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "igdb_id"
    t.datetime "igdb_synced_at"
    t.jsonb "igdb_data", default: {}, null: false
    t.boolean "guild_oriented", default: false, null: false
    t.boolean "verified_by_igdb", default: false, null: false
    t.datetime "deactivated_at"
    t.integer "deactivated_by_id"
    t.text "deactivation_reason"
    t.index ["deactivated_at"], name: "index_games_on_deactivated_at"
    t.index ["deactivated_by_id"], name: "index_games_on_deactivated_by_id"
    t.index ["guild_oriented"], name: "index_games_on_guild_oriented"
    t.index ["igdb_id"], name: "index_games_on_igdb_id", unique: true, where: "(igdb_id IS NOT NULL)"
    t.index ["name"], name: "index_games_on_name", unique: true
    t.index ["slug"], name: "index_games_on_slug", unique: true
    t.index ["verified_by_igdb"], name: "index_games_on_verified_by_igdb"
  end

  create_table "gear_snapshots", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "user_id", null: false
    t.bigint "game_id", null: false
    t.string "source", null: false
    t.text "raw_text"
    t.jsonb "data", default: {}, null: false
    t.text "embedding"
    t.boolean "validation_passed", default: true
    t.text "validation_warning"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_gear_snapshots_on_created_at"
    t.index ["data"], name: "index_gear_snapshots_on_data", using: :gin
    t.index ["game_id", "created_at"], name: "index_gear_snapshots_on_game_id_and_created_at"
    t.index ["game_id"], name: "index_gear_snapshots_on_game_id"
    t.index ["guild_id", "user_id", "created_at"], name: "index_gear_snapshots_latest"
    t.index ["guild_id", "user_id"], name: "index_gear_snapshots_on_guild_id_and_user_id"
    t.index ["guild_id"], name: "index_gear_snapshots_on_guild_id"
    t.index ["user_id"], name: "index_gear_snapshots_on_user_id"
  end

  create_table "gear_upload_requests", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "requester_id", null: false
    t.bigint "target_user_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "requested_at", null: false
    t.datetime "completed_at"
    t.string "discord_message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id", "target_user_id", "status"], name: "idx_on_guild_id_target_user_id_status_784bd620f4"
    t.index ["guild_id"], name: "index_gear_upload_requests_on_guild_id"
    t.index ["requested_at"], name: "index_gear_upload_requests_on_requested_at"
    t.index ["requester_id"], name: "index_gear_upload_requests_on_requester_id"
    t.index ["status"], name: "index_gear_upload_requests_on_status"
    t.index ["target_user_id"], name: "index_gear_upload_requests_on_target_user_id"
  end

  create_table "guild_activity_logs", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "user_id"
    t.string "action_type", null: false
    t.string "description", null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_guild_activity_logs_on_created_at"
    t.index ["guild_id", "action_type"], name: "index_guild_activity_logs_on_guild_id_and_action_type"
    t.index ["guild_id", "created_at"], name: "index_guild_activity_logs_on_guild_id_and_created_at", order: { created_at: :desc }
    t.index ["guild_id", "user_id"], name: "index_guild_activity_logs_on_guild_id_and_user_id"
    t.index ["guild_id"], name: "index_guild_activity_logs_on_guild_id"
    t.index ["subject_type", "subject_id"], name: "index_guild_activity_logs_on_subject"
    t.index ["user_id"], name: "index_guild_activity_logs_on_user_id"
  end

  create_table "guild_applications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "guild_id", null: false
    t.string "discord_username"
    t.integer "status", default: 0, null: false
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "character_details"
    t.index ["guild_id"], name: "index_guild_applications_on_guild_id"
    t.index ["user_id", "guild_id"], name: "index_guild_applications_on_user_and_guild_pending", unique: true, where: "(status = 0)"
    t.index ["user_id"], name: "index_guild_applications_on_user_id"
  end

  create_table "guild_discord_settings", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.string "discord_guild_id", null: false
    t.string "discord_guild_name"
    t.text "bot_token"
    t.string "events_channel_id"
    t.string "gear_channel_id"
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "polls_channel_id"
    t.string "loot_rolls_channel_id"
    t.string "default_timezone", default: "Eastern Time (US & Canada)"
    t.string "alliance_events_channel_id"
    t.string "alliance_polls_channel_id"
    t.string "alliance_loot_rolls_channel_id"
    t.string "alliance_invites_channel_id"
    t.index ["discord_guild_id"], name: "index_guild_discord_settings_on_discord_guild_id", unique: true
    t.index ["guild_id"], name: "index_guild_discord_settings_on_guild_id", unique: true
  end

  create_table "guild_document_folders", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "color", default: "#3b82f6"
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_guild_document_folders_on_guild_id"
    t.index ["user_id"], name: "index_guild_document_folders_on_user_id"
  end

  create_table "guild_document_images", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_guild_document_images_on_guild_id"
    t.index ["user_id"], name: "index_guild_document_images_on_user_id"
  end

  create_table "guild_documents", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.integer "visibility", default: 0, null: false
    t.text "content", default: "{}", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "folder_id"
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_guild_documents_on_deleted_at"
    t.index ["folder_id"], name: "index_guild_documents_on_folder_id"
    t.index ["guild_id", "visibility"], name: "index_guild_documents_on_guild_id_and_visibility"
    t.index ["guild_id"], name: "index_guild_documents_on_guild_id"
    t.index ["slug"], name: "index_guild_documents_on_slug", unique: true
    t.index ["user_id"], name: "index_guild_documents_on_user_id"
  end

  create_table "guild_games", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "game_id", null: false
    t.boolean "primary", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_guild_games_on_game_id"
    t.index ["guild_id", "game_id"], name: "index_guild_games_on_guild_id_and_game_id", unique: true
    t.index ["guild_id", "primary"], name: "index_guild_games_on_guild_id_and_primary", where: "(\"primary\" = true)"
    t.index ["guild_id"], name: "index_guild_games_on_guild_id"
  end

  create_table "guild_invite_links", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.string "token", null: false
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "expires_at"
    t.index ["created_by_id"], name: "index_guild_invite_links_on_created_by_id"
    t.index ["guild_id"], name: "index_guild_invite_links_on_guild_id"
    t.index ["token"], name: "index_guild_invite_links_on_token", unique: true
  end

  create_table "guild_invites", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "guild_id", null: false
    t.integer "status", default: 0
    t.bigint "invited_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "dismissed", default: false, null: false
    t.index ["guild_id"], name: "index_guild_invites_on_guild_id"
    t.index ["invited_by_id"], name: "index_guild_invites_on_invited_by_id"
    t.index ["user_id", "guild_id"], name: "index_guild_invites_on_user_id_and_guild_id", unique: true
    t.index ["user_id"], name: "index_guild_invites_on_user_id"
  end

  create_table "guild_member_tags", force: :cascade do |t|
    t.bigint "guild_member_id", null: false
    t.bigint "guild_tag_id", null: false
    t.bigint "assigned_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_by_id"], name: "index_guild_member_tags_on_assigned_by_id"
    t.index ["guild_member_id", "guild_tag_id"], name: "index_guild_member_tags_on_guild_member_id_and_guild_tag_id", unique: true
    t.index ["guild_member_id"], name: "index_guild_member_tags_on_guild_member_id"
    t.index ["guild_tag_id"], name: "index_guild_member_tags_on_guild_tag_id"
  end

  create_table "guild_member_warning_statuses", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "user_id", null: false
    t.bigint "warned_by_id"
    t.integer "warning_count", default: 0, null: false
    t.integer "state", default: 0, null: false
    t.text "last_warning_reason"
    t.datetime "last_warned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id", "user_id"], name: "idx_guild_member_warning_statuses_guild_user", unique: true
    t.index ["guild_id"], name: "index_guild_member_warning_statuses_on_guild_id"
    t.index ["user_id"], name: "index_guild_member_warning_statuses_on_user_id"
    t.index ["warned_by_id"], name: "index_guild_member_warning_statuses_on_warned_by_id"
  end

  create_table "guild_members", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "guild_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "joined_at", default: -> { "CURRENT_TIMESTAMP" }
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_role_id"
    t.index ["guild_id"], name: "index_guild_members_on_guild_id"
    t.index ["user_id", "guild_id"], name: "index_guild_members_on_user_id_and_guild_id", unique: true
    t.index ["user_id"], name: "index_guild_members_on_user_id"
  end

  create_table "guild_tags", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.string "name", null: false
    t.string "color", default: "#6366f1", null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_guild_tags_on_created_by_id"
    t.index ["guild_id", "name"], name: "index_guild_tags_on_guild_id_and_name", unique: true
    t.index ["guild_id"], name: "index_guild_tags_on_guild_id"
  end

  create_table "guilds", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "avatar_url"
    t.bigint "owner_id", null: false
    t.jsonb "settings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_id"
    t.text "accept_message"
    t.text "reject_message"
    t.string "permission_role_1_id"
    t.string "permission_role_2_id"
    t.boolean "role_1_can_manage_roles", default: false
    t.boolean "role_1_can_manage_applications", default: false
    t.boolean "role_1_can_manage_guild_settings", default: false
    t.boolean "role_2_can_manage_roles", default: false
    t.boolean "role_2_can_manage_applications", default: false
    t.boolean "role_2_can_manage_guild_settings", default: false
    t.string "permission_role_3_id"
    t.string "permission_role_4_id"
    t.boolean "role_3_can_manage_roles", default: false
    t.boolean "role_3_can_manage_applications", default: false
    t.boolean "role_3_can_manage_guild_settings", default: false
    t.boolean "role_4_can_manage_roles", default: false
    t.boolean "role_4_can_manage_applications", default: false
    t.boolean "role_4_can_manage_guild_settings", default: false
    t.string "default_role_id"
    t.boolean "role_1_can_kick_members", default: false
    t.boolean "role_2_can_kick_members", default: false
    t.boolean "role_3_can_kick_members", default: false
    t.boolean "role_4_can_kick_members", default: false
    t.boolean "role_1_can_manage_documents", default: false
    t.boolean "role_2_can_manage_documents", default: false
    t.boolean "role_3_can_manage_documents", default: false
    t.boolean "role_4_can_manage_documents", default: false
    t.boolean "role_1_can_manage_files", default: false
    t.boolean "role_2_can_manage_files", default: false
    t.boolean "role_3_can_manage_files", default: false
    t.boolean "role_4_can_manage_files", default: false
    t.boolean "publicly_listed", default: true, null: false
    t.boolean "role_1_can_manage_alliance", default: false, null: false
    t.boolean "role_2_can_manage_alliance", default: false, null: false
    t.boolean "role_3_can_manage_alliance", default: false, null: false
    t.boolean "role_4_can_manage_alliance", default: false, null: false
    t.datetime "archived_at"
    t.datetime "scheduled_purge_at"
    t.boolean "role_1_can_manage_warnings", default: false, null: false
    t.boolean "role_2_can_manage_warnings", default: false, null: false
    t.boolean "role_3_can_manage_warnings", default: false, null: false
    t.boolean "role_4_can_manage_warnings", default: false, null: false
    t.boolean "role_1_can_invite_alliance_guilds", default: false, null: false
    t.boolean "role_1_can_kick_alliance_guilds", default: false, null: false
    t.boolean "role_1_can_manage_tags", default: false, null: false
    t.boolean "role_2_can_invite_alliance_guilds", default: false, null: false
    t.boolean "role_2_can_kick_alliance_guilds", default: false, null: false
    t.boolean "role_2_can_manage_tags", default: false, null: false
    t.boolean "role_3_can_invite_alliance_guilds", default: false, null: false
    t.boolean "role_3_can_kick_alliance_guilds", default: false, null: false
    t.boolean "role_3_can_manage_tags", default: false, null: false
    t.boolean "role_4_can_invite_alliance_guilds", default: false, null: false
    t.boolean "role_4_can_kick_alliance_guilds", default: false, null: false
    t.boolean "role_4_can_manage_tags", default: false, null: false
    t.boolean "role_1_can_manage_events", default: false, null: false
    t.boolean "role_1_can_manage_polls", default: false, null: false
    t.boolean "role_1_can_manage_loot_rolls", default: false, null: false
    t.boolean "role_1_can_manage_discord_channels", default: false, null: false
    t.boolean "role_1_can_view_activity_feed", default: false, null: false
    t.boolean "role_1_can_export_members_csv", default: false, null: false
    t.boolean "role_1_can_use_message_center", default: false, null: false
    t.boolean "role_1_can_manage_gear_requests", default: false, null: false
    t.boolean "role_2_can_manage_events", default: false, null: false
    t.boolean "role_2_can_manage_polls", default: false, null: false
    t.boolean "role_2_can_manage_loot_rolls", default: false, null: false
    t.boolean "role_2_can_manage_discord_channels", default: false, null: false
    t.boolean "role_2_can_view_activity_feed", default: false, null: false
    t.boolean "role_2_can_export_members_csv", default: false, null: false
    t.boolean "role_2_can_use_message_center", default: false, null: false
    t.boolean "role_2_can_manage_gear_requests", default: false, null: false
    t.boolean "role_3_can_manage_events", default: false, null: false
    t.boolean "role_3_can_manage_polls", default: false, null: false
    t.boolean "role_3_can_manage_loot_rolls", default: false, null: false
    t.boolean "role_3_can_manage_discord_channels", default: false, null: false
    t.boolean "role_3_can_view_activity_feed", default: false, null: false
    t.boolean "role_3_can_export_members_csv", default: false, null: false
    t.boolean "role_3_can_use_message_center", default: false, null: false
    t.boolean "role_3_can_manage_gear_requests", default: false, null: false
    t.boolean "role_4_can_manage_events", default: false, null: false
    t.boolean "role_4_can_manage_polls", default: false, null: false
    t.boolean "role_4_can_manage_loot_rolls", default: false, null: false
    t.boolean "role_4_can_manage_discord_channels", default: false, null: false
    t.boolean "role_4_can_view_activity_feed", default: false, null: false
    t.boolean "role_4_can_export_members_csv", default: false, null: false
    t.boolean "role_4_can_use_message_center", default: false, null: false
    t.boolean "role_4_can_manage_gear_requests", default: false, null: false
    t.string "discord_invite_url"
    t.boolean "role_1_can_edit_gear_scanned_stats", default: false, null: false
    t.boolean "role_2_can_edit_gear_scanned_stats", default: false, null: false
    t.boolean "role_3_can_edit_gear_scanned_stats", default: false, null: false
    t.boolean "role_4_can_edit_gear_scanned_stats", default: false, null: false
    t.index ["archived_at"], name: "index_guilds_on_archived_at"
    t.index ["discord_id"], name: "index_guilds_on_discord_id"
    t.index ["owner_id", "name"], name: "index_guilds_on_owner_id_and_name", unique: true
    t.index ["owner_id"], name: "index_guilds_on_owner_id"
    t.index ["publicly_listed"], name: "index_guilds_on_publicly_listed"
    t.index ["scheduled_purge_at"], name: "index_guilds_on_scheduled_purge_at"
  end

  create_table "homepage_feature_card_images", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "homepage_feature_cards", force: :cascade do |t|
    t.string "slug", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "icon_key", null: false
    t.integer "position", default: 0, null: false
    t.boolean "visible", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_homepage_feature_cards_on_deleted_at"
    t.index ["slug"], name: "index_homepage_feature_cards_on_slug", unique: true
    t.index ["visible", "position"], name: "index_homepage_feature_cards_on_visible_and_position"
  end

  create_table "landing_comparison_rows", force: :cascade do |t|
    t.bigint "landing_comparison_table_id", null: false
    t.integer "position", null: false
    t.string "feature_label", null: false
    t.boolean "guildsync_included", default: true, null: false
    t.boolean "competitor_included", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["landing_comparison_table_id", "position"], name: "idx_landing_compare_rows_on_table_and_position", unique: true
    t.index ["landing_comparison_table_id"], name: "index_landing_comparison_rows_on_landing_comparison_table_id"
  end

  create_table "landing_comparison_tables", force: :cascade do |t|
    t.integer "position", null: false
    t.string "feature_column_label", default: "Feature", null: false
    t.string "guildsync_column_label", default: "GuildSync", null: false
    t.string "competitor_column_label", null: false
    t.boolean "show_guildsync_badge", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_landing_comparison_tables_on_position", unique: true
  end

  create_table "landing_user_feedbacks", force: :cascade do |t|
    t.integer "position", default: 0, null: false
    t.boolean "visible", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_landing_user_feedbacks_on_deleted_at"
    t.index ["visible", "position"], name: "index_landing_user_feedbacks_on_visible_and_position"
  end

  create_table "login_histories", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.text "user_agent"
    t.datetime "login_at", null: false
    t.datetime "logout_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["login_at"], name: "index_login_histories_on_login_at"
    t.index ["user_id"], name: "index_login_histories_on_user_id"
  end

  create_table "loot_roll_entries", force: :cascade do |t|
    t.bigint "loot_roll_id", null: false
    t.string "discord_user_id", null: false
    t.string "display_name", null: false
    t.integer "roll_value", null: false
    t.integer "discord_role_position"
    t.boolean "is_reroll", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "tiebreaker_round", default: 0, null: false
    t.index ["loot_roll_id", "discord_user_id"], name: "index_loot_roll_entries_unique_user", unique: true
    t.index ["loot_roll_id"], name: "index_loot_roll_entries_on_loot_roll_id"
    t.index ["roll_value"], name: "index_loot_roll_entries_on_roll_value"
  end

  create_table "loot_rolls", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.bigint "creator_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "min_roll", default: 1, null: false
    t.integer "max_roll", default: 100, null: false
    t.boolean "anonymous", default: false, null: false
    t.datetime "deadline_at"
    t.integer "status", default: 0, null: false
    t.string "discord_channel_id"
    t.string "discord_message_id"
    t.json "allowed_role_ids"
    t.bigint "winner_entry_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "current_tiebreaker_round", default: 0, null: false
    t.json "tied_discord_user_ids"
    t.datetime "deleted_at"
    t.index ["creator_id"], name: "index_loot_rolls_on_creator_id"
    t.index ["deadline_at"], name: "index_loot_rolls_on_deadline_at"
    t.index ["deleted_at"], name: "index_loot_rolls_on_deleted_at"
    t.index ["guild_id"], name: "index_loot_rolls_on_guild_id"
    t.index ["status"], name: "index_loot_rolls_on_status"
  end

  create_table "marketing_legal_pages", force: :cascade do |t|
    t.string "kind", null: false
    t.string "title", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_marketing_legal_pages_on_kind", unique: true
    t.index ["position"], name: "index_marketing_legal_pages_on_position", unique: true
  end

  create_table "moderation_audit_logs", force: :cascade do |t|
    t.bigint "admin_id"
    t.string "admin_email"
    t.string "action", null: false
    t.string "content_type"
    t.bigint "content_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_moderation_audit_logs_on_admin_id"
    t.index ["content_type", "content_id"], name: "index_moderation_audit_logs_on_content_type_and_content_id"
    t.index ["created_at"], name: "index_moderation_audit_logs_on_created_at"
  end

  create_table "moderation_flags", force: :cascade do |t|
    t.string "flaggable_type", null: false
    t.bigint "flaggable_id", null: false
    t.bigint "reported_by_id"
    t.string "reason"
    t.text "details"
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["flaggable_type", "flaggable_id"], name: "index_moderation_flags_on_flaggable_type_and_flaggable_id"
    t.index ["status"], name: "index_moderation_flags_on_status"
  end

  create_table "moderation_health_checks", force: :cascade do |t|
    t.string "check_id", null: false
    t.boolean "passed", default: true, null: false
    t.integer "warning_count", default: 0, null: false
    t.integer "fail_count", default: 0, null: false
    t.jsonb "details", default: {}
    t.datetime "next_run"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["check_id"], name: "index_moderation_health_checks_on_check_id", unique: true
    t.index ["created_at"], name: "index_moderation_health_checks_on_created_at"
    t.index ["passed"], name: "index_moderation_health_checks_on_passed"
  end

  create_table "ocr_denials", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "reason", null: false
    t.integer "current_usage", null: false
    t.integer "limit", null: false
    t.integer "hard_stop", null: false
    t.datetime "created_at", null: false
    t.index ["user_id", "created_at"], name: "index_ocr_denials_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_ocr_denials_on_user_id"
  end

  create_table "ocr_requests", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address", limit: 45
    t.string "user_agent", limit: 500
    t.datetime "created_at", null: false
    t.bigint "initiated_by_id"
    t.index ["created_at"], name: "index_ocr_requests_on_created_at"
    t.index ["initiated_by_id"], name: "index_ocr_requests_on_initiated_by_id"
    t.index ["ip_address"], name: "index_ocr_requests_on_ip_address"
    t.index ["user_id", "created_at"], name: "index_ocr_requests_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_ocr_requests_on_user_id"
  end

  create_table "ocr_usage_changes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "delta", null: false
    t.string "reason", null: false
    t.string "admin_email", null: false
    t.integer "before_used_period"
    t.integer "after_used_period"
    t.boolean "from_admin_panel", default: true, null: false
    t.string "action_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_ocr_usage_changes_on_created_at"
    t.index ["user_id", "created_at"], name: "index_ocr_usage_changes_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_ocr_usage_changes_on_user_id"
  end

  create_table "poll_votes", force: :cascade do |t|
    t.bigint "poll_id", null: false
    t.bigint "user_id"
    t.integer "choice", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_user_id"
    t.string "discord_username"
    t.index ["poll_id", "discord_user_id"], name: "index_poll_votes_on_poll_id_and_discord_user_id", unique: true, where: "(discord_user_id IS NOT NULL)"
    t.index ["poll_id", "user_id"], name: "index_poll_votes_on_poll_id_and_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["poll_id"], name: "index_poll_votes_on_poll_id"
    t.index ["user_id"], name: "index_poll_votes_on_user_id"
  end

  create_table "polls", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.datetime "deadline"
    t.boolean "anonymous"
    t.bigint "guild_id", null: false
    t.bigint "creator_id", null: false
    t.string "discord_message_id"
    t.string "discord_channel_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "discord_role_mentions"
    t.datetime "deleted_at"
    t.index ["creator_id"], name: "index_polls_on_creator_id"
    t.index ["deleted_at"], name: "index_polls_on_deleted_at"
    t.index ["guild_id"], name: "index_polls_on_guild_id"
  end

  create_table "pricing_plans", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "price", precision: 10, scale: 2
    t.string "price_display", null: false
    t.string "period", null: false
    t.text "description"
    t.boolean "popular", default: false, null: false
    t.boolean "active", default: true, null: false
    t.integer "max_guilds"
    t.integer "max_members_per_guild"
    t.jsonb "features", default: [], null: false
    t.integer "display_order", default: 0, null: false
    t.string "cta_text", default: "Get Started"
    t.string "cta_path", default: "/api/v1/auth/sign_up"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_price_id"
    t.string "stripe_price_id_annual"
    t.string "price_display_annual"
    t.integer "max_polls"
    t.integer "max_loot_rolls"
    t.integer "max_events"
    t.boolean "can_create_alliance", default: false, null: false
    t.jsonb "feature_entitlements", default: {}, null: false
    t.index ["active"], name: "index_pricing_plans_on_active"
    t.index ["display_order"], name: "index_pricing_plans_on_display_order"
    t.index ["name"], name: "index_pricing_plans_on_name", unique: true
  end

  create_table "profanity_update_logs", force: :cascade do |t|
    t.datetime "timestamp", null: false
    t.jsonb "sources_checked", default: []
    t.integer "new_words_added", default: 0, null: false
    t.integer "words_removed", default: 0, null: false
    t.integer "total_words", default: 0, null: false
    t.jsonb "error_messages", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_profanity_update_logs_on_created_at"
  end

  create_table "react_roles", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.integer "position", null: false
    t.string "role_id", null: false
    t.string "role_name", null: false
    t.string "emoji_name", null: false
    t.string "emoji_id"
    t.boolean "is_custom_emoji", default: false, null: false
    t.string "channel_id"
    t.string "message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id", "message_id"], name: "idx_react_roles_guild_message"
    t.index ["guild_id", "position"], name: "index_react_roles_on_guild_id_and_position", unique: true
    t.index ["guild_id"], name: "index_react_roles_on_guild_id"
  end

  create_table "signup_email_verifications", force: :cascade do |t|
    t.string "email", null: false
    t.string "token_digest"
    t.datetime "expires_at"
    t.datetime "verified_at"
    t.datetime "sent_at"
    t.integer "send_count", default: 0, null: false
    t.string "last_sent_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["email"], name: "index_signup_email_verifications_on_email"
    t.index ["expires_at"], name: "index_signup_email_verifications_on_expires_at"
    t.index ["token_digest"], name: "index_signup_email_verifications_on_token_digest", unique: true
    t.index ["user_id"], name: "index_signup_email_verifications_on_user_id"
    t.index ["user_id"], name: "index_signup_email_verifications_one_pending_per_user", unique: true, where: "((verified_at IS NULL) AND (user_id IS NOT NULL))"
    t.index ["verified_at"], name: "index_signup_email_verifications_on_verified_at"
  end

  create_table "site_settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_site_settings_on_key", unique: true
  end

  create_table "stripe_webhook_events", force: :cascade do |t|
    t.string "stripe_event_id", null: false
    t.string "event_type", null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_event_id"], name: "index_stripe_webhook_events_on_stripe_event_id", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "pricing_plan_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "started_at", null: false
    t.datetime "expires_at"
    t.datetime "canceled_at"
    t.string "stripe_subscription_id"
    t.string "stripe_customer_id"
    t.datetime "trial_ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_price_id"
    t.datetime "trial_warning_sent_at"
    t.datetime "first_paid_invoice_at"
    t.index ["first_paid_invoice_at"], name: "index_subscriptions_on_first_paid_invoice_at"
    t.index ["pricing_plan_id"], name: "index_subscriptions_on_pricing_plan_id"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.index ["trial_warning_sent_at"], name: "index_subscriptions_on_trial_warning_sent_at"
    t.index ["user_id", "status"], name: "index_subscriptions_on_user_id_and_status"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "user_compliance_warnings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "warning_type", null: false
    t.boolean "active", default: true, null: false
    t.text "message", null: false
    t.jsonb "details_json", default: {}, null: false
    t.integer "conflict_count", default: 0, null: false
    t.boolean "locked_by_policy", default: false, null: false
    t.datetime "last_detected_at"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "warning_type"], name: "index_ucw_on_user_and_type", unique: true
    t.index ["user_id"], name: "index_user_compliance_warnings_on_user_id"
    t.index ["warning_type", "active"], name: "index_ucw_on_type_and_active"
  end

  create_table "user_discord_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "discord_user_id", null: false
    t.text "access_token", null: false
    t.text "refresh_token"
    t.datetime "expires_at"
    t.text "scopes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discord_username"
    t.index ["discord_user_id"], name: "index_user_discord_connections_on_discord_user_id", unique: true
    t.index ["user_id"], name: "index_user_discord_connections_on_user_id", unique: true
  end

  create_table "user_recent_activities", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "path", limit: 2048, null: false
    t.string "label", limit: 500, null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "link_path", limit: 2048
    t.index ["subject_type", "subject_id"], name: "index_user_recent_activities_on_subject"
    t.index ["user_id", "created_at"], name: "index_user_recent_activities_on_user_id_and_created_at", order: { created_at: :desc }
    t.index ["user_id"], name: "index_user_recent_activities_on_user_id"
  end

  create_table "user_warnings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "issued_by_id", null: false
    t.string "reason"
    t.string "level", default: "warning"
    t.datetime "expires_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_user_warnings_on_expires_at"
    t.index ["issued_by_id"], name: "index_user_warnings_on_issued_by_id"
    t.index ["user_id"], name: "index_user_warnings_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "username"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "otp_secret"
    t.boolean "mfa_enabled", default: false, null: false
    t.boolean "mfa_verified", default: false, null: false
    t.string "discord_user_id"
    t.string "discord_username"
    t.string "discord_avatar_url"
    t.boolean "discord_connected", default: false, null: false
    t.integer "auth_method", default: 0, null: false
    t.datetime "locked_at"
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.string "plan"
    t.boolean "archived", default: false, null: false
    t.string "preferred_locale", limit: 5
    t.datetime "trial_started_at"
    t.datetime "trial_ends_at"
    t.string "billing_plan"
    t.integer "ocr_requests_used", default: 0, null: false
    t.integer "ocr_requests_limit"
    t.string "billing_status"
    t.string "ocr_billing_plan"
    t.datetime "ocr_last_reset_at"
    t.boolean "ocr_hard_locked", default: false, null: false
    t.boolean "ocr_unlocked", default: false, null: false
    t.datetime "trial_expired_at"
    t.text "ocr_notes"
    t.integer "ocr_requests_used_this_period", default: 0, null: false
    t.string "signup_ip", limit: 45
    t.datetime "last_backup_generation_at"
    t.string "last_backup_generation_ip"
    t.string "discord_global_name"
    t.boolean "beta_features_enabled", default: false, null: false
    t.jsonb "alliance_downgrade_snapshot", default: {}, null: false
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.datetime "registration_completed_at"
    t.datetime "signup_email_verified_at"
    t.datetime "backup_code_acknowledged_at"
    t.datetime "backup_code_regenerated_at"
    t.datetime "account_closed_at"
    t.datetime "account_deletion_started_at"
    t.datetime "account_data_purged_at"
    t.datetime "account_closure_soft_completed_at"
    t.string "google_uid"
    t.string "microsoft_uid"
    t.index ["account_closed_at"], name: "index_users_on_account_closed_at"
    t.index ["account_closure_soft_completed_at"], name: "index_users_on_account_closure_soft_completed_at"
    t.index ["account_data_purged_at"], name: "index_users_on_account_data_purged_at"
    t.index ["archived"], name: "index_users_on_archived"
    t.index ["backup_code_regenerated_at"], name: "index_users_on_backup_code_regenerated_at"
    t.index ["billing_plan"], name: "index_users_on_billing_plan"
    t.index ["billing_status"], name: "index_users_on_billing_status"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["discord_user_id"], name: "index_users_on_discord_user_id", unique: true, where: "(discord_user_id IS NOT NULL)"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true, where: "(google_uid IS NOT NULL)"
    t.index ["mfa_enabled"], name: "index_users_on_mfa_enabled"
    t.index ["microsoft_uid"], name: "index_users_on_microsoft_uid", unique: true, where: "(microsoft_uid IS NOT NULL)"
    t.index ["ocr_billing_plan"], name: "index_users_on_ocr_billing_plan"
    t.index ["ocr_hard_locked"], name: "index_users_on_ocr_hard_locked"
    t.index ["ocr_unlocked"], name: "index_users_on_ocr_unlocked"
    t.index ["registration_completed_at"], name: "index_users_on_registration_completed_at"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["signup_email_verified_at"], name: "index_users_on_signup_email_verified_at"
    t.index ["signup_ip"], name: "index_users_on_signup_ip"
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
    t.index ["stripe_subscription_id"], name: "index_users_on_stripe_subscription_id", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.index ["trial_ends_at"], name: "index_users_on_trial_ends_at"
    t.index ["trial_expired_at"], name: "index_users_on_trial_expired_at"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.bigint "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object"
    t.text "object_changes"
    t.datetime "created_at"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "account_deletion_requests", "users", on_delete: :cascade
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "alliance_activity_logs", "alliances"
  add_foreign_key "alliance_activity_logs", "guilds"
  add_foreign_key "alliance_activity_logs", "users"
  add_foreign_key "alliance_disband_votes", "alliances"
  add_foreign_key "alliance_disband_votes", "guilds"
  add_foreign_key "alliance_disband_votes", "users"
  add_foreign_key "alliance_event_discord_messages", "alliance_events"
  add_foreign_key "alliance_event_discord_messages", "guilds"
  add_foreign_key "alliance_event_discord_signups", "alliance_events"
  add_foreign_key "alliance_event_participations", "alliance_events"
  add_foreign_key "alliance_event_participations", "users"
  add_foreign_key "alliance_events", "alliances"
  add_foreign_key "alliance_events", "users", column: "created_by_id"
  add_foreign_key "alliance_guilds", "alliances"
  add_foreign_key "alliance_guilds", "guilds"
  add_foreign_key "alliance_guilds", "users", column: "invited_by_user_id"
  add_foreign_key "alliance_invites", "alliances"
  add_foreign_key "alliance_invites", "guilds"
  add_foreign_key "alliance_invites", "users", column: "invited_by_user_id"
  add_foreign_key "alliance_join_requests", "alliances"
  add_foreign_key "alliance_join_requests", "guilds", column: "requesting_guild_id"
  add_foreign_key "alliance_join_requests", "users", column: "requested_by_user_id"
  add_foreign_key "alliance_loot_roll_discord_messages", "alliance_loot_rolls"
  add_foreign_key "alliance_loot_roll_discord_messages", "guilds"
  add_foreign_key "alliance_loot_roll_entries", "alliance_loot_rolls"
  add_foreign_key "alliance_loot_roll_entries", "users"
  add_foreign_key "alliance_loot_rolls", "alliances"
  add_foreign_key "alliance_loot_rolls", "users", column: "creator_id"
  add_foreign_key "alliance_member_tags", "alliance_members"
  add_foreign_key "alliance_member_tags", "alliance_tags"
  add_foreign_key "alliance_member_tags", "users", column: "assigned_by_id"
  add_foreign_key "alliance_members", "alliances"
  add_foreign_key "alliance_members", "guilds"
  add_foreign_key "alliance_members", "users"
  add_foreign_key "alliance_messages", "alliances"
  add_foreign_key "alliance_messages", "users", column: "sender_id"
  add_foreign_key "alliance_poll_discord_messages", "alliance_polls"
  add_foreign_key "alliance_poll_discord_messages", "guilds"
  add_foreign_key "alliance_poll_votes", "alliance_polls"
  add_foreign_key "alliance_poll_votes", "users"
  add_foreign_key "alliance_polls", "alliances"
  add_foreign_key "alliance_polls", "users", column: "creator_id"
  add_foreign_key "alliance_tags", "alliances"
  add_foreign_key "alliance_tags", "users", column: "created_by_id"
  add_foreign_key "alliances", "guilds", column: "leader_guild_id"
  add_foreign_key "alliances", "users", column: "leader_user_id"
  add_foreign_key "backup_code_usage_logs", "backup_codes"
  add_foreign_key "backup_code_usage_logs", "users"
  add_foreign_key "backup_codes", "users"
  add_foreign_key "direct_messages", "guilds"
  add_foreign_key "direct_messages", "users", column: "recipient_id"
  add_foreign_key "direct_messages", "users", column: "sender_id"
  add_foreign_key "discord_connections", "guilds"
  add_foreign_key "discord_connections", "users"
  add_foreign_key "discord_event_participations", "events"
  add_foreign_key "discord_event_signups", "discord_events"
  add_foreign_key "discord_events", "discord_connections"
  add_foreign_key "discord_events", "guilds"
  add_foreign_key "discord_role_syncs", "guilds"
  add_foreign_key "event_participations", "events"
  add_foreign_key "event_participations", "users"
  add_foreign_key "events", "guilds"
  add_foreign_key "events", "users", column: "created_by_id"
  add_foreign_key "feature_request_comments", "feature_requests"
  add_foreign_key "feature_request_comments", "users"
  add_foreign_key "feature_request_votes", "feature_requests"
  add_foreign_key "feature_request_votes", "users"
  add_foreign_key "feature_requests", "users"
  add_foreign_key "file_entries", "folders"
  add_foreign_key "file_entries", "guilds"
  add_foreign_key "folders", "folders", column: "parent_folder_id"
  add_foreign_key "folders", "guilds"
  add_foreign_key "games", "users", column: "deactivated_by_id", on_delete: :nullify
  add_foreign_key "gear_snapshots", "games"
  add_foreign_key "gear_snapshots", "guilds"
  add_foreign_key "gear_snapshots", "users"
  add_foreign_key "gear_upload_requests", "guilds"
  add_foreign_key "gear_upload_requests", "users", column: "requester_id"
  add_foreign_key "gear_upload_requests", "users", column: "target_user_id"
  add_foreign_key "guild_activity_logs", "guilds"
  add_foreign_key "guild_activity_logs", "users"
  add_foreign_key "guild_applications", "guilds"
  add_foreign_key "guild_applications", "users"
  add_foreign_key "guild_discord_settings", "guilds"
  add_foreign_key "guild_document_folders", "guilds"
  add_foreign_key "guild_document_folders", "users"
  add_foreign_key "guild_document_images", "guilds"
  add_foreign_key "guild_document_images", "users"
  add_foreign_key "guild_documents", "guild_document_folders", column: "folder_id"
  add_foreign_key "guild_documents", "guilds"
  add_foreign_key "guild_documents", "users"
  add_foreign_key "guild_games", "games"
  add_foreign_key "guild_games", "guilds"
  add_foreign_key "guild_invite_links", "guilds"
  add_foreign_key "guild_invite_links", "users", column: "created_by_id"
  add_foreign_key "guild_invites", "guilds"
  add_foreign_key "guild_invites", "users"
  add_foreign_key "guild_invites", "users", column: "invited_by_id"
  add_foreign_key "guild_member_tags", "guild_members"
  add_foreign_key "guild_member_tags", "guild_tags"
  add_foreign_key "guild_member_tags", "users", column: "assigned_by_id"
  add_foreign_key "guild_member_warning_statuses", "guilds"
  add_foreign_key "guild_member_warning_statuses", "users"
  add_foreign_key "guild_member_warning_statuses", "users", column: "warned_by_id"
  add_foreign_key "guild_members", "guilds"
  add_foreign_key "guild_members", "users"
  add_foreign_key "guild_tags", "guilds"
  add_foreign_key "guild_tags", "users", column: "created_by_id"
  add_foreign_key "guilds", "users", column: "owner_id"
  add_foreign_key "landing_comparison_rows", "landing_comparison_tables"
  add_foreign_key "login_histories", "users"
  add_foreign_key "loot_roll_entries", "loot_rolls"
  add_foreign_key "loot_rolls", "guilds"
  add_foreign_key "loot_rolls", "users", column: "creator_id"
  add_foreign_key "ocr_denials", "users"
  add_foreign_key "ocr_requests", "users"
  add_foreign_key "ocr_requests", "users", column: "initiated_by_id"
  add_foreign_key "ocr_usage_changes", "users"
  add_foreign_key "poll_votes", "polls"
  add_foreign_key "poll_votes", "users"
  add_foreign_key "polls", "guilds"
  add_foreign_key "polls", "users", column: "creator_id"
  add_foreign_key "react_roles", "guilds"
  add_foreign_key "signup_email_verifications", "users"
  add_foreign_key "subscriptions", "pricing_plans"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "user_compliance_warnings", "users"
  add_foreign_key "user_discord_connections", "users"
  add_foreign_key "user_recent_activities", "users"
end
