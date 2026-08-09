require "test_helper"

class CarpoolOfferTest < ActiveSupport::TestCase
  setup do
    @event = events(:chickens_tomorrow)
    @user  = users(:ala)
    Participation.create!(event: @event, user: @user, status: :confirmed, position: 1)
  end

  test "valid offer from a confirmed participant saves" do
    offer = CarpoolOffer.new(event: @event, user: @user)
    assert offer.valid?, offer.errors.full_messages.inspect
  end

  test "non-participant cannot offer to drive" do
    offer = CarpoolOffer.new(event: @event, user: users(:bartek))
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("uczestnicy") }
  end

  test "cancelled participant counts as non-participant" do
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:cancelled])
    offer = CarpoolOffer.new(event: @event, user: @user)
    refute offer.valid?
  end

  test "waitlist participant cannot offer to drive" do
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:waitlist])
    offer = CarpoolOffer.new(event: @event, user: @user)
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("zapisani uczestnicy") }
  end

  test "reserved participant cannot offer to drive" do
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:reserved])
    offer = CarpoolOffer.new(event: @event, user: @user)
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("zapisani uczestnicy") }
  end

  test "offer becomes invalid if participant slips from confirmed onto waitlist" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    Participation.where(event: @event, user: @user).update_all(status: Participation.statuses[:waitlist])
    refute offer.reload.valid?
  end

  test "(event, user) is unique" do
    CarpoolOffer.create!(event: @event, user: @user)
    dup = CarpoolOffer.new(event: @event, user: @user)
    refute dup.valid?
    assert dup.errors.of_kind?(:user_id, :taken)
  end

  test "SEATS constant is 4" do
    assert_equal 4, CarpoolOffer::SEATS
  end

  test "seats accounting reflects accepted requests only" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    assert_equal 0, offer.seats_taken
    assert_equal 4, offer.seats_left
    refute offer.full?

    b = users(:bartek); c = users(:cezary); d = users(:dominika)
    [ b, c, d ].each { |u| Participation.create!(event: @event, user: u, status: :confirmed, position: 99) }

    CarpoolRequest.create!(carpool_offer: offer, user: b, status: :pending)   # pending nie liczy
    CarpoolRequest.create!(carpool_offer: offer, user: c, status: :accepted)
    CarpoolRequest.create!(carpool_offer: offer, user: d, status: :declined)  # declined nie liczy

    assert_equal 1, offer.reload.seats_taken
    assert_equal 3, offer.seats_left
    refute offer.full?
  end

  test "destroying the offer cascades to carpool_requests" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    bartek = users(:bartek)
    Participation.create!(event: @event, user: bartek, status: :confirmed, position: 2)
    CarpoolRequest.create!(carpool_offer: offer, user: bartek, status: :pending)
    assert_difference "CarpoolRequest.count", -1 do
      offer.destroy
    end
  end

  test "destroying the event cascades to offers" do
    CarpoolOffer.create!(event: @event, user: @user)
    assert_difference "CarpoolOffer.count", -1 do
      @event.destroy
    end
  end

  test "destroying the user cascades to their offers" do
    CarpoolOffer.create!(event: @event, user: @user)
    assert_difference "CarpoolOffer.count", -1 do
      @user.destroy
    end
  end

  test "user without can_drive flag cannot create an offer" do
    @user.update!(can_drive: false)
    offer = CarpoolOffer.new(event: @event, user: @user)
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("uprawnień") }
  end

  test "user with can_drive=true creates offer successfully" do
    @user.update!(can_drive: true)
    assert CarpoolOffer.new(event: @event, user: @user).valid?
  end

  # ---- Trip state ----

  test "default trip_state is :not_started" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    assert_equal "not_started", offer.trip_state
    assert_nil offer.current_pickup_user_id
  end

  test "depart! flips state to :en_route and clears pickup" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    bartek = users(:bartek)
    Participation.create!(event: @event, user: bartek, status: :confirmed, position: 99)
    CarpoolRequest.create!(carpool_offer: offer, user: bartek, status: :accepted)
    offer.update!(trip_state: :picking_up, current_pickup_user: bartek)

    offer.depart!
    assert_equal "en_route", offer.reload.trip_state
    assert_nil offer.current_pickup_user_id
  end

  test "arrive_at!(user) sets state to :picking_up + current_pickup_user" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    bartek = users(:bartek)
    Participation.create!(event: @event, user: bartek, status: :confirmed, position: 99)
    CarpoolRequest.create!(carpool_offer: offer, user: bartek, status: :accepted)

    offer.arrive_at!(bartek)
    assert_equal "picking_up", offer.reload.trip_state
    assert_equal bartek.id, offer.current_pickup_user_id
  end

  test "cancel_trip! resets to :not_started + clears pickup" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    bartek = users(:bartek)
    Participation.create!(event: @event, user: bartek, status: :confirmed, position: 99)
    CarpoolRequest.create!(carpool_offer: offer, user: bartek, status: :accepted)
    offer.arrive_at!(bartek)

    offer.cancel_trip!
    assert_equal "not_started", offer.reload.trip_state
    assert_nil offer.current_pickup_user_id
  end

  test "current_pickup_user must be an accepted passenger of the offer" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    bartek = users(:bartek)
    Participation.create!(event: @event, user: bartek, status: :confirmed, position: 99)
    # Bartek nie ma CarpoolRequest accepted → nie może być picked up.
    offer.current_pickup_user = bartek
    offer.trip_state = :picking_up
    refute offer.valid?
    assert offer.errors[:current_pickup_user_id].any?
  end

  test "current_pickup_user with declined request still rejected" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    bartek = users(:bartek)
    Participation.create!(event: @event, user: bartek, status: :confirmed, position: 99)
    CarpoolRequest.create!(carpool_offer: offer, user: bartek, status: :declined)
    offer.current_pickup_user = bartek
    offer.trip_state = :picking_up
    refute offer.valid?
  end

  test "passengers_in_pickup_order bez pozycji spada na kolejność akceptacji (updated_at)" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    b = users(:bartek); c = users(:cezary); d = users(:dominika)
    [ b, c, d ].each { |u| Participation.create!(event: @event, user: u, status: :confirmed, position: 99) }

    # Tworzymy w odwrotnej kolejności i akceptujemy ręcznie żeby updated_at szedł
    # zgodnie z momentem akceptacji, nie momentem stworzenia request-a.
    req_d = CarpoolRequest.create!(carpool_offer: offer, user: d, status: :pending)
    req_c = CarpoolRequest.create!(carpool_offer: offer, user: c, status: :pending)
    req_b = CarpoolRequest.create!(carpool_offer: offer, user: b, status: :pending)

    travel_to 1.minute.from_now  do; req_b.update!(status: :accepted); end
    travel_to 2.minutes.from_now do; req_c.update!(status: :accepted); end
    travel_to 3.minutes.from_now do; req_d.update!(status: :accepted); end
    travel_back

    assert_equal [ b.id, c.id, d.id ], offer.passengers_in_pickup_order.map(&:id)
  end

  test "depart!(ordered_user_ids) zapisuje pickup_position i steruje kolejnością odbierania" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    b = users(:bartek); c = users(:cezary)
    [ b, c ].each { |u| Participation.create!(event: @event, user: u, status: :confirmed, position: 99) }
    req_b = CarpoolRequest.create!(carpool_offer: offer, user: b, status: :accepted)
    req_c = CarpoolRequest.create!(carpool_offer: offer, user: c, status: :accepted)

    offer.depart!([ c.id, b.id ])

    assert_equal "en_route", offer.reload.trip_state
    assert_equal 1, req_c.reload.pickup_position
    assert_equal 2, req_b.reload.pickup_position
    assert_equal [ c.id, b.id ], offer.passengers_in_pickup_order.map(&:id)
    assert_equal c.id, offer.first_pickup_user.id
  end

  test "depart! ignoruje obce id, pominiętych zaakceptowanych dokleja na końcu" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    b = users(:bartek); c = users(:cezary); d = users(:dominika)
    [ b, c, d ].each { |u| Participation.create!(event: @event, user: u, status: :confirmed, position: 99) }
    req_b = CarpoolRequest.create!(carpool_offer: offer, user: b, status: :pending)
    req_c = CarpoolRequest.create!(carpool_offer: offer, user: c, status: :pending)
    req_d = CarpoolRequest.create!(carpool_offer: offer, user: d, status: :pending)
    travel_to 1.minute.from_now  do; req_b.update!(status: :accepted); end
    travel_to 2.minutes.from_now do; req_c.update!(status: :accepted); end
    travel_to 3.minutes.from_now do; req_d.update!(status: :accepted); end
    travel_back

    # Kierowca podał tylko [d, obcy] — c i b (pominięci) idą na koniec
    # w kolejności akceptacji; obce id nie wywala i niczego nie dodaje.
    offer.depart!([ d.id, users(:ala).id ])

    assert_equal [ d.id, b.id, c.id ], offer.passengers_in_pickup_order.map(&:id)
    assert_equal [ 1, 2, 3 ], [ req_d, req_b, req_c ].map { |r| r.reload.pickup_position }
  end

  test "depart! bez kolejności nie rusza istniejących pickup_position" do
    offer = CarpoolOffer.create!(event: @event, user: @user)
    b = users(:bartek)
    Participation.create!(event: @event, user: b, status: :confirmed, position: 99)
    req_b = CarpoolRequest.create!(carpool_offer: offer, user: b, status: :accepted, pickup_position: 7)

    offer.depart!
    assert_equal "en_route", offer.reload.trip_state
    assert_equal 7, req_b.reload.pickup_position
  end
end
