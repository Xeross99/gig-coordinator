class AddPremiumToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :premium, :boolean, default: false, null: false
    add_column :users, :player_card, :string
  end
end
