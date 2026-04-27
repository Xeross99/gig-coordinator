class AddMessagesCountToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :messages_count, :integer, default: 0, null: false
    Event.reset_column_information
    Event.find_each do |event|
      Event.where(id: event.id).update_all(messages_count: event.messages.count)
    end
  end

  def down
    remove_column :events, :messages_count
  end
end
