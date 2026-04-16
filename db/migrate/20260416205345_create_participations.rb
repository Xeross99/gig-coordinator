class CreateParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :participations do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true
      t.integer    :status,   null: false, default: 0
      t.integer    :position, null: false, default: 0

      t.timestamps
    end
    add_index :participations, [ :event_id, :user_id ], unique: true
    add_index :participations, [ :event_id, :status, :position ]
  end
end
