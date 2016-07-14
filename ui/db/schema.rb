# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20160701171400) do

  create_table "clusters", force: :cascade do |t|
    t.string  "name",                  limit: 255
    t.string  "app",                   limit: 255
    t.string  "rw_host",               limit: 255
    t.integer "port",                  limit: 4
    t.boolean "admin_review_required"
    t.boolean "is_staging"
  end

  add_index "clusters", ["name"], name: "index_clusters_on_name", unique: true, using: :btree

  create_table "comments", force: :cascade do |t|
    t.text     "comment",      limit: 65535
    t.string   "author",       limit: 255
    t.datetime "created_at",                 null: false
    t.integer  "migration_id", limit: 4
    t.datetime "updated_at",                 null: false
  end

  add_index "comments", ["migration_id"], name: "index_comments_on_migration_id", using: :btree

  create_table "meta_requests", force: :cascade do |t|
    t.text     "ddl_statement",  limit: 65535, null: false
    t.text     "final_insert",   limit: 65535
    t.string   "requestor",      limit: 255,   null: false
    t.string   "pr_url",         limit: 255,   null: false
    t.datetime "created_at",                   null: false
    t.datetime "updated_at",                   null: false
    t.binary   "custom_options", limit: 65535
  end

  create_table "migrations", force: :cascade do |t|
    t.datetime "created_at",                                     null: false
    t.datetime "updated_at"
    t.datetime "completed_at"
    t.string   "requestor",        limit: 255,                   null: false
    t.string   "cluster_name",     limit: 128,                   null: false
    t.string   "database",         limit: 255,                   null: false
    t.text     "ddl_statement",    limit: 65535,                 null: false
    t.text     "final_insert",     limit: 65535
    t.string   "pr_url",           limit: 255,                   null: false
    t.integer  "table_rows_start", limit: 8
    t.integer  "table_rows_end",   limit: 8
    t.integer  "table_size_start", limit: 8
    t.integer  "table_size_end",   limit: 8
    t.integer  "index_size_start", limit: 8
    t.integer  "index_size_end",   limit: 8
    t.string   "approved_by",      limit: 255
    t.datetime "approved_at"
    t.string   "work_directory",   limit: 255
    t.datetime "started_at"
    t.integer  "copy_percentage",  limit: 4
    t.boolean  "staged",                         default: true
    t.integer  "status",           limit: 4,     default: 0
    t.text     "error_message",    limit: 65535
    t.string   "run_host",         limit: 255
    t.integer  "lock_version",     limit: 4,     default: 0,     null: false
    t.boolean  "editable",                       default: true
    t.integer  "runtype",          limit: 1,     default: 0
    t.integer  "meta_request_id",  limit: 4
    t.integer  "initial_runtype",  limit: 1,     default: 0
    t.boolean  "auto_run",                       default: false
    t.binary   "custom_options",   limit: 65535
  end

  add_index "migrations", ["status"], name: "index_migrations_on_status", using: :btree

  create_table "owners", force: :cascade do |t|
    t.string "cluster_name", limit: 255
    t.string "username",     limit: 255
  end

  add_index "owners", ["cluster_name", "username"], name: "index_owners_on_cluster_name_and_username", unique: true, using: :btree

  create_table "shift_files", force: :cascade do |t|
    t.integer  "migration_id", limit: 4
    t.integer  "file_type",    limit: 1
    t.datetime "created_at"
    t.datetime "updated_at"
    t.binary   "contents",     limit: 4294967295
  end

  add_index "shift_files", ["migration_id", "file_type"], name: "index_shift_files_on_migration_id_and_file_type", unique: true, using: :btree

  create_table "statuses", force: :cascade do |t|
    t.integer "status",      limit: 4
    t.string  "description", limit: 255
    t.string  "action",      limit: 255
    t.string  "label",       limit: 255
  end

  add_index "statuses", ["status"], name: "index_statuses_on_status", unique: true, using: :btree

end
