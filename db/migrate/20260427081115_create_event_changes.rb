class CreateEventChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :event_changes do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :field,          null: false
      t.string :previous_value
      t.string :new_value
      t.timestamps
    end

    add_index :event_changes, %i[event_id created_at]
  end
end
