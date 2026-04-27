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

ActiveRecord::Schema[8.1].define(version: 2026_04_27_145112) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "carpool_offers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "event_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["event_id", "user_id"], name: "index_carpool_offers_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_carpool_offers_on_event_id"
    t.index ["user_id"], name: "index_carpool_offers_on_user_id"
  end

  create_table "carpool_requests", force: :cascade do |t|
    t.integer "carpool_offer_id", null: false
    t.datetime "created_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["carpool_offer_id", "user_id"], name: "index_carpool_requests_on_carpool_offer_id_and_user_id", unique: true
    t.index ["user_id", "carpool_offer_id"], name: "index_carpool_requests_on_user_id_and_carpool_offer_id"
  end

  create_table "event_changes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "event_id", null: false
    t.string "field", null: false
    t.string "new_value"
    t.string "previous_value"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["event_id", "created_at"], name: "index_event_changes_on_event_id_and_created_at"
    t.index ["event_id"], name: "index_event_changes_on_event_id"
    t.index ["user_id"], name: "index_event_changes_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.integer "capacity", null: false
    t.integer "changes_count", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "creator_id"
    t.datetime "ends_at", null: false
    t.integer "host_id", null: false
    t.integer "messages_count", default: 0, null: false
    t.string "name", null: false
    t.decimal "pay_per_person", precision: 8, scale: 2, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_events_on_creator_id"
    t.index ["ends_at"], name: "index_events_on_ends_at"
    t.index ["host_id"], name: "index_events_on_host_id"
    t.index ["scheduled_at"], name: "index_events_on_scheduled_at"
  end

  create_table "host_blocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "host_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["host_id", "user_id"], name: "index_host_blocks_on_host_id_and_user_id"
    t.index ["user_id", "host_id"], name: "index_host_blocks_on_user_id_and_host_id", unique: true
  end

  create_table "host_managers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "host_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["host_id", "user_id"], name: "index_host_managers_on_host_id_and_user_id"
    t.index ["user_id", "host_id"], name: "index_host_managers_on_user_id_and_host_id", unique: true
  end

  create_table "hosts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "location", null: false
    t.string "phone"
    t.datetime "updated_at", null: false
    t.index "LOWER(first_name), last_name", name: "index_hosts_on_lower_first_name_and_last_name", unique: true
    t.index ["email"], name: "index_hosts_on_email", unique: true
  end

  create_table "login_codes", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.integer "authenticatable_id", null: false
    t.string "authenticatable_type", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.string "user_agent"
    t.index ["authenticatable_type", "authenticatable_id"], name: "index_login_codes_on_authenticatable"
    t.index ["code"], name: "index_login_codes_on_code"
    t.index ["expires_at"], name: "index_login_codes_on_expires_at"
  end

  create_table "messages", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "event_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["event_id", "created_at"], name: "index_messages_on_event_id_and_created_at"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "participation_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "event_type", null: false
    t.integer "participation_id", null: false
    t.index ["participation_id"], name: "index_participation_events_on_participation_id"
  end

  create_table "participations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "event_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "reserved_until"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["event_id", "status", "position"], name: "index_participations_on_event_id_and_status_and_position"
    t.index ["event_id", "user_id"], name: "index_participations_on_event_id_and_user_id", unique: true
    t.index ["reserved_until"], name: "index_participations_on_reserved_until"
    t.index ["user_id"], name: "index_participations_on_user_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "p256dh_key", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "authenticatable_id", null: false
    t.string "authenticatable_type", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["authenticatable_type", "authenticatable_id"], name: "index_sessions_on_authenticatable"
    t.index ["token"], name: "index_sessions_on_token", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.boolean "can_drive", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.datetime "last_seen_at"
    t.string "phone"
    t.integer "title", default: 0
    t.datetime "updated_at", null: false
    t.index "LOWER(first_name), last_name", name: "index_users_on_lower_first_name_and_last_name", unique: true
    t.index ["admin"], name: "index_users_on_admin", where: "admin = true"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["title"], name: "index_users_on_title"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "carpool_offers", "events"
  add_foreign_key "carpool_offers", "users"
  add_foreign_key "carpool_requests", "carpool_offers"
  add_foreign_key "carpool_requests", "users"
  add_foreign_key "event_changes", "events", on_delete: :cascade
  add_foreign_key "event_changes", "users", on_delete: :nullify
  add_foreign_key "events", "hosts"
  add_foreign_key "events", "users", column: "creator_id"
  add_foreign_key "host_blocks", "hosts"
  add_foreign_key "host_blocks", "users"
  add_foreign_key "host_managers", "hosts"
  add_foreign_key "host_managers", "users"
  add_foreign_key "messages", "events"
  add_foreign_key "messages", "users"
  add_foreign_key "participation_events", "participations"
  add_foreign_key "participations", "events"
  add_foreign_key "participations", "users"
  add_foreign_key "push_subscriptions", "users"
end
