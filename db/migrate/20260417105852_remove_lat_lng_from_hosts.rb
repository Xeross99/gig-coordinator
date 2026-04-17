class RemoveLatLngFromHosts < ActiveRecord::Migration[8.1]
  def change
    remove_column :hosts, :lat, :decimal, precision: 10, scale: 6
    remove_column :hosts, :lng, :decimal, precision: 10, scale: 6
  end
end
