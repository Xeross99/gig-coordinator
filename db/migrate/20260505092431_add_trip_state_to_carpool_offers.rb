class AddTripStateToCarpoolOffers < ActiveRecord::Migration[8.1]
  # Carpool trip status: kierowca powiadamia pasażerów krok po kroku
  # ("Wyjeżdżam", "Jestem u: X"). Stan trzymamy na CarpoolOffer (jeden offer
  # = jedno auto = jedna trasa). `current_pickup_user_id` to sentinel — kogo
  # kierowca aktualnie odbiera; null gdy `trip_state != picking_up`.
  def change
    add_column :carpool_offers, :trip_state, :integer, default: 0, null: false
    add_reference :carpool_offers, :current_pickup_user, foreign_key: { to_table: :users }, null: true
  end
end
