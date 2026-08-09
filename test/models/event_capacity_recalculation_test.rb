require "test_helper"

class EventCapacityRecalculationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    # Ensure no user is mistrz_piora by default — prevents seed_reservations interference
    User.update_all(title: User.titles[:kurnikowy_gangster])
  end

  def valid_attrs(overrides = {})
    {
      host: hosts(:jan),
      name: "Lapanie kur",
      scheduled_at: 2.days.from_now,
      ends_at: 2.days.from_now + 3.hours,
      pay_per_person: 150.0,
      capacity: 6
    }.merge(overrides)
  end

  def join!(event, user)
    Event.transaction do
      event.lock!
      event = Event.find(event.id)
      status = event.full? ? :waitlist : :confirmed
      pos = (event.participations.where(status: status).maximum(:position) || 0) + 1
      event.participations.create!(user: user, status: status, position: pos)
    end
  end

  # --- Capacity increase: promote from waitlist by join order ----------------

  test "increasing capacity promotes waitlisters in order of joining (position)" do
    event = Event.create!(valid_attrs(capacity: 2))

    join!(event, users(:ala))
    join!(event, users(:bartek))
    join!(event, users(:cezary))
    join!(event, users(:dominika))

    assert_equal 2, event.participations.confirmed.count
    assert_equal 2, event.participations.waitlist.count

    event.update!(capacity: 4)

    assert_equal 4, event.participations.confirmed.count
    assert_equal 0, event.participations.waitlist.count

    cezary_p = event.participations.find_by(user: users(:cezary))
    dominika_p = event.participations.find_by(user: users(:dominika))
    assert_equal "confirmed", cezary_p.status
    assert_equal "confirmed", dominika_p.status
  end

  test "increasing capacity by one promotes only the first waitlister" do
    event = Event.create!(valid_attrs(capacity: 2))

    join!(event, users(:ala))
    join!(event, users(:bartek))
    join!(event, users(:cezary))
    join!(event, users(:dominika))

    event.update!(capacity: 3)

    assert_equal 3, event.participations.confirmed.count
    assert_equal 1, event.participations.waitlist.count

    cezary_p = event.participations.find_by(user: users(:cezary))
    dominika_p = event.participations.find_by(user: users(:dominika))
    assert_equal "confirmed", cezary_p.status, "Cezary joined first on waitlist, should be promoted"
    assert_equal "waitlist", dominika_p.status, "Dominika joined second, should stay on waitlist"
  end

  # --- Capacity decrease: demote most recent confirmed ----------------------

  test "decreasing capacity demotes most recently confirmed to waitlist" do
    event = Event.create!(valid_attrs(capacity: 4))

    join!(event, users(:ala))
    join!(event, users(:bartek))
    join!(event, users(:cezary))
    join!(event, users(:dominika))

    assert_equal 4, event.participations.confirmed.count

    event.update!(capacity: 2)

    assert_equal 2, event.participations.confirmed.count
    assert_equal 2, event.participations.waitlist.count

    ala_p = event.participations.find_by(user: users(:ala))
    bartek_p = event.participations.find_by(user: users(:bartek))
    assert_equal "confirmed", ala_p.status, "Ala joined first, should keep confirmed"
    assert_equal "confirmed", bartek_p.status, "Bartek joined second, should keep confirmed"

    cezary_p = event.participations.find_by(user: users(:cezary))
    dominika_p = event.participations.find_by(user: users(:dominika))
    assert_equal "waitlist", cezary_p.status
    assert_equal "waitlist", dominika_p.status
  end

  # --- Mistrz Piora priority ------------------------------------------------

  test "mistrz piora reserved slots are preserved when capacity decreases" do
    users(:ala).update!(title: :mistrz_piora)
    event = Event.create!(valid_attrs(capacity: 4))

    ala_p = event.participations.find_by(user: users(:ala))
    assert_equal "reserved", ala_p.status, "Mistrz piora should get reservation"

    join!(event, users(:bartek))
    join!(event, users(:cezary))
    join!(event, users(:dominika))

    # capacity 4: 1 reserved (ala) + 3 confirmed = 4 slots taken
    event.update!(capacity: 2)

    ala_p.reload
    assert_equal "reserved", ala_p.status, "Mistrz piora reservation should NOT be demoted"

    # Demote compares confirmed vs capacity (not slots_taken vs capacity)
    # capacity 2: 3 confirmed - 2 = 1 overflow → demote 1
    assert_equal 2, event.participations.confirmed.count
    assert_equal 1, event.participations.waitlist.count
  end

  test "mistrz piora gets reservation even when event is created with low capacity" do
    users(:ala).update!(title: :mistrz_piora)
    users(:bartek).update!(title: :mistrz_piora)

    event = Event.create!(valid_attrs(capacity: 1))

    reserved = event.participations.reserved.includes(:user).map(&:user)
    assert_includes reserved, users(:ala)
    assert_includes reserved, users(:bartek)
    assert event.slots_taken > event.capacity, "Mistrz piora reservations exceed capacity"
  end

  test "increasing capacity with mistrz piora reserved promotes waitlisters first" do
    users(:ala).update!(title: :mistrz_piora)
    event = Event.create!(valid_attrs(capacity: 2))

    # ala gets reserved (1 slot), bartek gets confirmed (1 slot) = full
    join!(event, users(:bartek))
    join!(event, users(:cezary))
    join!(event, users(:dominika))

    event.update!(capacity: 4)

    cezary_p = event.participations.find_by(user: users(:cezary))
    dominika_p = event.participations.find_by(user: users(:dominika))
    assert_equal "confirmed", cezary_p.status, "Cezary should be promoted from waitlist"
    assert_equal "confirmed", dominika_p.status, "Dominika should be promoted from waitlist"

    ala_p = event.participations.find_by(user: users(:ala))
    assert_equal "reserved", ala_p.status, "Mistrz piora stays reserved (invitation flow)"
  end

  # --- Round-trip: decrease then increase -----------------------------------

  test "capacity decrease then increase restores demoted users in correct order" do
    event = Event.create!(valid_attrs(capacity: 4))

    join!(event, users(:ala))
    join!(event, users(:bartek))
    join!(event, users(:cezary))
    join!(event, users(:dominika))

    event.update!(capacity: 2)

    cezary_p = event.participations.find_by(user: users(:cezary))
    dominika_p = event.participations.find_by(user: users(:dominika))
    assert_equal "waitlist", cezary_p.status
    assert_equal "waitlist", dominika_p.status

    event.update!(capacity: 3)

    cezary_p.reload
    dominika_p.reload
    assert_equal "confirmed", cezary_p.status, "Cezary was demoted first, lands at front of waitlist, promoted first"
    assert_equal "waitlist", dominika_p.status, "Only one slot opened, Dominika stays on waitlist"
  end

  # --- Edge cases -----------------------------------------------------------

  test "increasing capacity with empty waitlist does nothing extra" do
    event = Event.create!(valid_attrs(capacity: 2))

    join!(event, users(:ala))

    assert_no_difference -> { event.participations.confirmed.count } do
      event.update!(capacity: 5)
    end
  end

  test "capacity change does not affect cancelled participations" do
    event = Event.create!(valid_attrs(capacity: 3))

    join!(event, users(:ala))
    join!(event, users(:bartek))
    p = event.participations.find_by(user: users(:bartek))
    p.update!(status: :cancelled)

    event.update!(capacity: 1)

    p.reload
    assert_equal "cancelled", p.status, "Cancelled participation should not be touched"
  end
end
