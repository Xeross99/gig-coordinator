class AddCanDriveToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :can_drive, :boolean, null: false, default: false
  end
end
