class AddTitleToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :title, :integer
    add_index  :users, :title

    User.reset_column_information
    User.where(title: nil).find_each do |u|
      u.update_column(:title, rand(4))
    end
  end

  def down
    remove_index  :users, :title
    remove_column :users, :title
  end
end
