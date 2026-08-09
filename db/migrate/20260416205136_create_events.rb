class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :host, null: false, foreign_key: true
      t.string   :name,           null: false
      t.datetime :scheduled_at,   null: false
      t.datetime :ends_at,        null: false
      t.decimal  :pay_per_person, null: false, precision: 8, scale: 2
      t.integer  :capacity,       null: false
      t.datetime :completed_at

      t.timestamps
    end
    add_index :events, :scheduled_at
    add_index :events, :ends_at
  end
end
