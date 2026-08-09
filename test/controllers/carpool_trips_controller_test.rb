require "test_helper"

class CarpoolTripsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event     = events(:chickens_tomorrow)
    @driver    = users(:ala)
    @passenger = users(:bartek)
    @other     = users(:cezary)
    Participation.create!(event: @event, user: @driver,    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: @passenger, status: :confirmed, position: 2)
    Participation.create!(event: @event, user: @other,     status: :confirmed, position: 3)
    @offer = CarpoolOffer.create!(event: @event, user: @driver)
    @passenger_req = CarpoolRequest.create!(carpool_offer: @offer, user: @passenger, status: :accepted)
    @other_req     = CarpoolRequest.create!(carpool_offer: @offer, user: @other,     status: :accepted)
  end

  # ---- Auth / driver guard ----

  test "depart requires login" do
    post depart_event_carpool_trip_path(@event)
    assert_redirected_to login_path
  end

  test "depart redirects when signed-in user is not the driver of this offer" do
    sign_in_as(@passenger)
    post depart_event_carpool_trip_path(@event)
    assert_redirected_to event_path(@event)
    assert_match "Nie jesteś kierowcą", flash[:alert]
    assert_equal "not_started", @offer.reload.trip_state
  end

  # ---- depart ----

  test "depart flips trip_state to en_route and enqueues :carpool_departed push" do
    sign_in_as(@driver)
    assert_enqueued_with(job: WebPushNotifier, args: [ :carpool_departed, { carpool_offer_id: @offer.id } ]) do
      post depart_event_carpool_trip_path(@event)
    end
    assert_equal "en_route", @offer.reload.trip_state
    assert_redirected_to event_path(@event)
  end

  test "depart z pickup_order zapisuje kolejność odbierania z modalu" do
    sign_in_as(@driver)
    post depart_event_carpool_trip_path(@event), params: { pickup_order: [ @other.id.to_s, @passenger.id.to_s ] }

    assert_equal "en_route", @offer.reload.trip_state
    assert_equal 1, @other_req.reload.pickup_position
    assert_equal 2, @passenger_req.reload.pickup_position
  end

  # ---- widok panelu kierowcy ----

  test "przed wyjazdem kierowca widzi modal z inputami pickup_order[] dla każdego pasażera" do
    sign_in_as(@driver)
    get event_path(@event)
    assert_response :success
    assert_match "Kolejność odbierania", response.body
    assert_match %(name="pickup_order[]" value="#{@passenger.id}"), response.body
    assert_match %(name="pickup_order[]" value="#{@other.id}"), response.body
  end

  test "po wyjeździe guziki Jestem u idą w kolejności odbierania" do
    sign_in_as(@driver)
    post depart_event_carpool_trip_path(@event), params: { pickup_order: [ @other.id, @passenger.id ] }
    get event_path(@event)
    assert_response :success
    assert_match "Jestem u:", response.body
    other_pos     = response.body.index(pickup_event_carpool_trip_path(@event, user_id: @other.id))
    passenger_pos = response.body.index(pickup_event_carpool_trip_path(@event, user_id: @passenger.id))
    assert other_pos < passenger_pos, "pasażer z pickup_position=1 powinien renderować się pierwszy"
  end

  # ---- pickup ----

  test "pickup sets current_pickup_user, fires :carpool_at_pickup + :carpool_progress" do
    sign_in_as(@driver)
    assert_enqueued_with(job: WebPushNotifier, args: [ :carpool_at_pickup, { carpool_offer_id: @offer.id, user_id: @passenger.id } ]) do
      assert_enqueued_with(job: WebPushNotifier, args: [ :carpool_progress, { carpool_offer_id: @offer.id, user_id: @passenger.id } ]) do
        post pickup_event_carpool_trip_path(@event), params: { user_id: @passenger.id }
      end
    end
    @offer.reload
    assert_equal "picking_up", @offer.trip_state
    assert_equal @passenger.id, @offer.current_pickup_user_id
  end

  test "pickup rejects user_id that is not an accepted passenger of this offer" do
    sign_in_as(@driver)
    outsider = users(:dominika)
    Participation.create!(event: @event, user: outsider, status: :confirmed, position: 99)

    post pickup_event_carpool_trip_path(@event), params: { user_id: outsider.id }
    assert_redirected_to event_path(@event)
    assert_match "nie jest na liście", flash[:alert]
    assert_equal "not_started", @offer.reload.trip_state
  end

  test "pickup overwrites previously selected current_pickup_user" do
    sign_in_as(@driver)
    @offer.arrive_at!(@passenger)
    post pickup_event_carpool_trip_path(@event), params: { user_id: @other.id }
    assert_equal @other.id, @offer.reload.current_pickup_user_id
  end

  # ---- cancel ----

  test "cancel resets state silently — bez push do pasażerów" do
    # „Anuluj wyjazd" ma nową semantykę: „mam wszystkich, koniec trasy".
    # Pasażerowie już są w aucie, nie ma kogo informować.
    sign_in_as(@driver)
    @offer.arrive_at!(@passenger)
    assert_no_enqueued_jobs only: WebPushNotifier do
      post cancel_event_carpool_trip_path(@event)
    end
    @offer.reload
    assert_equal "not_started", @offer.trip_state
    assert_nil @offer.current_pickup_user_id
    assert_match "zakończona", flash[:notice]
  end

  # ---- event lock ----

  test "depart no-op once event has started" do
    sign_in_as(@driver)
    @event.update_columns(scheduled_at: 1.hour.ago, ends_at: 1.hour.from_now)
    post depart_event_carpool_trip_path(@event)
    assert_redirected_to event_path(@event)
    assert_match "się rozpoczęło", flash[:alert]
    assert_equal "not_started", @offer.reload.trip_state
  end
end
