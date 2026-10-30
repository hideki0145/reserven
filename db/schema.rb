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

ActiveRecord::Schema[8.1].define(version: 2026_10_30_000002) do
  create_table "items", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "disabled", default: false, null: false
    t.string "reason_policy", default: "none", null: false
    t.integer "seq", default: 0, null: false
    t.index ["seq"], name: "index_items_on_seq"
  end

  create_table "usages", force: :cascade do |t|
    t.integer "item_id"
    t.integer "user_id"
    t.string "item_name_snapshot", null: false
    t.string "user_name_snapshot", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "finished_at"
    t.string "finish_reason"
    t.integer "finished_by_id"
    t.string "finished_by_name_snapshot"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "created_by_id"
    t.string "created_by_name_snapshot"
    t.integer "updated_by_id"
    t.string "updated_by_name_snapshot"
    t.text "reason"
    t.index ["created_by_id"], name: "index_usages_on_created_by_id"
    t.index ["finished_by_id"], name: "index_usages_on_finished_by_id"
    t.index ["item_id", "finished_at"], name: "index_usages_on_item_id_and_finished_at"
    t.index ["item_id"], name: "index_usages_on_item_id"
    t.index ["updated_by_id"], name: "index_usages_on_updated_by_id"
    t.index ["user_id"], name: "index_usages_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "remember_digest"
    t.boolean "disabled", default: false, null: false
    t.integer "seq", default: 0, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["seq"], name: "index_users_on_seq"
  end

  add_foreign_key "usages", "items"
  add_foreign_key "usages", "users"
  add_foreign_key "usages", "users", column: "created_by_id"
  add_foreign_key "usages", "users", column: "finished_by_id"
  add_foreign_key "usages", "users", column: "updated_by_id"
end
