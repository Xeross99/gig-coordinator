class CreateParticipationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :participation_events do |t|
      t.references :participation, null: false, foreign_key: true, index: true
      t.integer :event_type, null: false
      t.datetime :created_at, null: false
    end
  end
end
