class AddCalendarTokenToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :calendar_token, :string
    add_index  :users, :calendar_token, unique: true

    User.reset_column_information
    User.where(calendar_token: nil).find_each do |u|
      u.update_column(:calendar_token, SecureRandom.hex(20))
    end
  end

  def down
    remove_index  :users, :calendar_token
    remove_column :users, :calendar_token
  end
end
