require "test_helper"

class CarpoolTripStateTest < ActiveSupport::TestCase
  setup do
    @event  = events(:chickens_tomorrow)
    @driver = users(:ala)
    @driver.update!(can_drive: true)
    Participation.create!(event: @event, user: @driver, status: :confirmed, position: 1)
    @offer = CarpoolOffer.create!(event: @event, user: @driver)
  end

  def accept_passenger(user, position: 99)
    user.update!(can_drive: true)
    Participation.create!(event: @event, user: user, status: :confirmed, position: position)
    CarpoolRequest.create!(carpool_offer: @offer, user: user, status: :accepted)
  end

  # --- depart! -----------------------------------------------------------------

  test "depart!(ordered_user_ids) assigns pickup_position in the given order and flips to en_route" do
    b = users(:bartek); c = users(:cezary)
    req_b = accept_passenger(b, position: 2)
    req_c = accept_passenger(c, position: 3)

    @offer.depart!([ c.id, b.id ])

    assert_equal "en_route", @offer.reload.trip_state
    assert_nil @offer.current_pickup_user_id
    assert_equal 1, req_c.reload.pickup_position
    assert_equal 2, req_b.reload.pickup_position
    assert_equal [ c.id, b.id ], @offer.passengers_in_pickup_order.map(&:id)
  end

  test "depart! ignores unknown ids and appends unlisted accepted passengers by updated_at" do
    b = users(:bartek); c = users(:cezary); d = users(:dominika)
    req_b = accept_passenger(b, position: 2)
    req_c = accept_passenger(c, position: 3)
    req_d = accept_passenger(d, position: 4)

    # Re-stamp updated_at so the "unlisted" tail order is deterministic: b then c.
    travel_to 1.minute.from_now  do req_b.touch end
    travel_to 2.minutes.from_now do req_c.touch end
    travel_back

    # Only d is listed (plus a bogus id). b and c fall to the tail by updated_at.
    @offer.depart!([ d.id, 999_999 ])

    assert_equal [ d.id, b.id, c.id ], @offer.passengers_in_pickup_order.map(&:id)
    assert_equal [ 1, 2, 3 ], [ req_d, req_b, req_c ].map { |r| r.reload.pickup_position }
  end

  test "depart! with no order leaves existing pickup positions untouched" do
    b = users(:bartek)
    req_b = accept_passenger(b, position: 2)
    req_b.update!(pickup_position: 5)

    @offer.depart!

    assert_equal "en_route", @offer.reload.trip_state
    assert_equal 5, req_b.reload.pickup_position
  end

  # --- arrive_at! / cancel_trip! ----------------------------------------------

  test "arrive_at!(user) sets picking_up and current_pickup_user" do
    b = users(:bartek)
    accept_passenger(b, position: 2)

    @offer.arrive_at!(b)

    assert_equal "picking_up", @offer.reload.trip_state
    assert_equal b.id, @offer.current_pickup_user_id
  end

  test "cancel_trip! resets to not_started and clears current_pickup_user" do
    b = users(:bartek)
    accept_passenger(b, position: 2)
    @offer.arrive_at!(b)

    @offer.cancel_trip!

    assert_equal "not_started", @offer.reload.trip_state
    assert_nil @offer.current_pickup_user_id
  end

  # --- passengers_in_pickup_order fallback ------------------------------------

  test "passengers_in_pickup_order puts NULL positions last, ordered by updated_at" do
    b = users(:bartek); c = users(:cezary); d = users(:dominika)
    req_b = accept_passenger(b, position: 2)  # will get an explicit position
    req_c = accept_passenger(c, position: 3)  # NULL position
    req_d = accept_passenger(d, position: 4)  # NULL position

    req_b.update!(pickup_position: 1)
    # c confirmed (updated) before d → c precedes d among the NULL tail
    travel_to 1.minute.from_now  do req_c.touch end
    travel_to 2.minutes.from_now do req_d.touch end
    travel_back

    assert_equal [ b.id, c.id, d.id ], @offer.passengers_in_pickup_order.map(&:id)
  end

  # --- offer validations -------------------------------------------------------

  test "offer rejected when user is not a confirmed participant" do
    non_participant = users(:bartek)
    non_participant.update!(can_drive: true)
    offer = CarpoolOffer.new(event: @event, user: non_participant)
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("uczestnicy") }
  end

  test "offer rejected when user lacks can_drive?" do
    @driver.update!(can_drive: false)
    offer = CarpoolOffer.new(event: @event, user: @driver)
    # (@driver already has a confirmed participation but no more drive permission)
    refute offer.valid?
    assert offer.errors[:base].any? { |m| m.include?("uprawnień") }
  end

  test "offer rejected when user is already a passenger on the event" do
    b = users(:bartek)
    accept_passenger(b, position: 2)  # b is now an accepted passenger of @offer

    b_offer = CarpoolOffer.new(event: @event, user: b)
    refute b_offer.valid?
    assert b_offer.errors[:base].any? { |m| m.include?("pasażerem") }
  end
end
