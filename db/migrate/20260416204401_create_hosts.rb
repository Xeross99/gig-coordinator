class CreateHosts < ActiveRecord::Migration[8.1]
  def change
    create_table :hosts do |t|
      t.string  :first_name, null: false
      t.string  :last_name,  null: false
      t.string  :email,      null: false
      t.string  :location,   null: false
      t.decimal :lat, precision: 10, scale: 6
      t.decimal :lng, precision: 10, scale: 6

      t.timestamps
    end
    add_index :hosts, :email, unique: true
  end
end
