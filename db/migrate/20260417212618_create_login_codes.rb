class CreateLoginCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :login_codes do |t|
      t.string   :authenticatable_type, null: false
      t.integer  :authenticatable_id,   null: false
      t.string   :code,                 null: false
      t.datetime :expires_at,           null: false
      t.datetime :used_at
      t.integer  :attempts,             null: false, default: 0
      t.string   :ip_address
      t.string   :user_agent

      t.timestamps
    end

    add_index :login_codes, %i[authenticatable_type authenticatable_id], name: "index_login_codes_on_authenticatable"
    add_index :login_codes, :code
    add_index :login_codes, :expires_at
  end
end
