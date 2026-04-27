class AddChangesCountToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :changes_count, :integer, default: 0, null: false
    Event.reset_column_information
    Event.find_each do |event|
      Event.where(id: event.id).update_all(changes_count: event.changes_log.count)
    end
  end

  def down
    remove_column :events, :changes_count
  end
end
