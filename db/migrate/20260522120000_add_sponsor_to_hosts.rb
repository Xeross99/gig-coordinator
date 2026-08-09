class AddSponsorToHosts < ActiveRecord::Migration[8.1]
  def change
    add_column :hosts, :supporter, :boolean, default: false, null: false
  end
end
