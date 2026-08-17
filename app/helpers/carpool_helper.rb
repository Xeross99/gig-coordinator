module CarpoolHelper
  # Which message a passenger sees. Trip state crosses with "is this about me",
  # so the branching happens once here and the view gets a flat `case` instead
  # of an `elsif` chain. nil = nothing to show.
  def carpool_passenger_state(offer)
    if offer.en_route?
      return :departed_for_me    if offer.first_pickup?(Current.user)
      return :departed_for_other if offer.first_pickup_user
      :departed
    elsif offer.picking_up?
      return :at_my_place if offer.current_pickup?(Current.user)
      :at_other_place     if offer.current_pickup_user
    end
  end

  # Green only when the trip is about this passenger right now; every other
  # state stays blue so it does not steal attention.
  MY_TURN_STATES = %i[departed_for_me at_my_place].freeze

  def carpool_passenger_panel_classes(offer)
    if MY_TURN_STATES.include?(carpool_passenger_state(offer))
      "border-emerald-300 bg-emerald-50 text-emerald-900"
    else
      "border-sky-200 bg-white text-sky-900"
    end
  end
end
