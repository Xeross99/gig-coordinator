class AddPhoneToUsersAndHosts < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :phone, :string
    add_column :hosts, :phone, :string
  end
end
