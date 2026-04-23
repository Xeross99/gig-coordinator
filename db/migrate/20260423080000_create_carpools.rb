class CreateCarpools < ActiveRecord::Migration[8.1]
  def change
    create_table :carpool_offers do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true, index: false
      t.timestamps
    end
    add_index :carpool_offers, [ :event_id, :user_id ], unique: true
    add_index :carpool_offers, :user_id

    create_table :carpool_requests do |t|
      t.references :carpool_offer, null: false, foreign_key: true, index: false
      t.references :user,          null: false, foreign_key: true, index: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :carpool_requests, [ :carpool_offer_id, :user_id ], unique: true
    add_index :carpool_requests, [ :user_id, :carpool_offer_id ]
  end
end
