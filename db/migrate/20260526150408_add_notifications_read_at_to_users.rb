class AddNotificationsReadAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notifications_read_at, :datetime
  end
end
