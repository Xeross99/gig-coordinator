class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.string     :token, null: false
      t.references :authenticatable, polymorphic: true, null: false
      t.string     :user_agent
      t.string     :ip_address

      t.timestamps
    end
    add_index :sessions, :token, unique: true
  end
end
