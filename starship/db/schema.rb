# This file is auto-generated from the current state of the database. Instead of editing this file, 
# please use the migrations feature of Active Record to incrementally modify your database, and
# then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your database schema. If you need
# to create the application database on another system, you should be using db:schema:load, not running
# all the migrations from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 25) do

  create_table "delays", :force => true do |t|
    t.string  "name",    :limit => 64
    t.integer "seconds", :limit => 11
  end

  add_index "delays", ["name"], :name => "name"

  create_table "deliveries", :force => true do |t|
    t.string "name", :limit => 64, :default => "", :null => false
  end

  add_index "deliveries", ["name"], :name => "name"

  create_table "messages", :force => true do |t|
    t.integer  "msg_type_id", :limit => 11,  :null => false
    t.string   "sender"
    t.string   "subject",     :limit => 128
    t.text     "body"
    t.datetime "created",                    :null => false
  end

  add_index "messages", ["msg_type_id"], :name => "fk_messages_msgtype"
  add_index "messages", ["sender"], :name => "sender"
  add_index "messages", ["created"], :name => "created"

  create_table "messages_people", :force => true do |t|
    t.integer  "message_id", :limit => 11
    t.integer  "person_id",  :limit => 11,                   :null => false
    t.string   "header",     :limit => 16, :default => "to", :null => false
    t.integer  "delay",      :limit => 4,  :default => 0
    t.datetime "sent",                                       :null => false
  end

  add_index "messages_people", ["message_id", "person_id", "header"], :name => "msg_id"
  add_index "messages_people", ["sent"], :name => "sent_idx"

  create_table "msg_types", :force => true do |t|
    t.string   "msgtype",      :limit => 64
    t.datetime "added",                      :null => false
    t.integer  "defaultdelay", :limit => 11
    t.text     "description"
  end

  add_index "msg_types", ["msgtype"], :name => "msgtype"

  create_table "msg_types_parameters", :force => true do |t|
    t.integer "msg_type_id",  :limit => 11, :null => false
    t.integer "parameter_id", :limit => 11, :null => false
    t.text    "description"
  end

  add_index "msg_types_parameters", ["msg_type_id", "parameter_id"], :name => "msg_type_parameter_id", :unique => true

  create_table "notification_parameters", :force => true do |t|
    t.integer "notification_id", :limit => 11, :null => false
    t.integer "parameter_id",    :limit => 11
    t.string  "value"
  end

  add_index "notification_parameters", ["notification_id"], :name => "index_notification_parameters_on_notification_id"
  add_index "notification_parameters", ["parameter_id"], :name => "index_notification_parameters_on_msg_type_parameter_id"

  create_table "notifications", :force => true do |t|
    t.integer  "msg_type_id", :limit => 11, :null => false
    t.datetime "received"
    t.string   "sender",      :limit => 64
    t.datetime "generated"
  end

  add_index "notifications", ["generated"], :name => "index_notifications_on_generated"

  create_table "parameters", :force => true do |t|
    t.string "name",    :limit => 64
    t.string "hr_name"
  end

  create_table "persons", :force => true do |t|
    t.string  "email"
    t.string  "name"
    t.string  "jid"
    t.string  "stringid"
    t.boolean "admin",           :default => false
    t.string  "hashed_password"
    t.string  "salt"
  end

  create_table "subscription_filters", :force => true do |t|
    t.integer "subscription_id", :limit => 11, :null => false
    t.integer "parameter_id",    :limit => 11, :null => false
    t.string  "operator",                      :null => false
    t.string  "filterstring",                  :null => false
  end

  add_index "subscription_filters", ["subscription_id"], :name => "subscription_id"
  add_index "subscription_filters", ["parameter_id"], :name => "parameter_id"

  create_table "subscriptions", :force => true do |t|
    t.integer "msg_type_id", :limit => 11,                   :null => false
    t.integer "person_id",   :limit => 11,                   :null => false
    t.integer "delay_id",    :limit => 11
    t.integer "delivery_id", :limit => 11
    t.text    "comment"
    t.boolean "private"
    t.boolean "enabled",                   :default => true
  end

  add_index "subscriptions", ["person_id", "msg_type_id"], :name => "person_id"

end
