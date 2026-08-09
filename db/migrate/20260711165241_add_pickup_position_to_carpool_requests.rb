class AddPickupPositionToCarpoolRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :carpool_requests, :pickup_position, :integer
  end
end
