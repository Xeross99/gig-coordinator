class ChangeUsersTitleDefault < ActiveRecord::Migration[8.1]
  def up
    change_column_default :users, :title, from: nil, to: 0
    User.reset_column_information
    User.where(title: nil).update_all(title: 0)
  end

  def down
    change_column_default :users, :title, from: 0, to: nil
  end
end
