class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
    # Roll-up — lista czatu leci zawsze po `(event_id, created_at)` rosnąco.
    add_index :messages, [ :event_id, :created_at ]
  end
end
