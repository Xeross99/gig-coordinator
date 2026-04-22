require "test_helper"

class EventTest < ActiveSupport::TestCase
  def valid_attrs(overrides = {})
    {
      host: hosts(:jan),
      name: "Lapanie kur",
      scheduled_at: 2.days.from_now,
      ends_at: 2.days.from_now + 3.hours,
      pay_per_person: 150.0,
      capacity: 4
    }.merge(overrides)
  end

  test "valid event can be created" do
    assert Event.new(valid_attrs).valid?
  end

  test "requires name, scheduled_at, ends_at, pay_per_person, capacity, host" do
    e = Event.new
    refute e.valid?
    %i[name scheduled_at ends_at pay_per_person capacity host].each do |attr|
      assert e.errors[attr].any?, "expected errors on #{attr}"
    end
  end

  test "capacity must be positive integer" do
    refute Event.new(valid_attrs(capacity: 0)).valid?
    refute Event.new(valid_attrs(capacity: -1)).valid?
  end

  test "pay_per_person must be non-negative" do
    refute Event.new(valid_attrs(pay_per_person: -1)).valid?
    assert Event.new(valid_attrs(pay_per_person: 0)).valid?
  end

  test "ends_at must be after scheduled_at" do
    e = Event.new(valid_attrs(scheduled_at: 2.days.from_now, ends_at: 1.day.from_now))
    refute e.valid?
    assert e.errors[:ends_at].any?
  end

  test "scope :upcoming returns future events ordered by scheduled_at" do
    Event.delete_all
    past  = Event.create!(valid_attrs(scheduled_at: 3.days.ago,   ends_at: 3.days.ago + 2.hours, name: "past"))
    soon  = Event.create!(valid_attrs(scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours, name: "soon"))
    later = Event.create!(valid_attrs(scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours, name: "later"))
    assert_equal [ soon, later ], Event.upcoming.to_a
    refute_includes Event.upcoming, past
  end

  test "scope :awaiting_completion returns events past ends_at with no completed_at" do
    Event.delete_all
    ended  = Event.create!(valid_attrs(scheduled_at: 3.hours.ago, ends_at: 1.hour.ago, name: "ended"))
    done   = Event.create!(valid_attrs(scheduled_at: 4.hours.ago, ends_at: 2.hours.ago, completed_at: Time.current, name: "done"))
    future = Event.create!(valid_attrs(scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours, name: "future"))
    assert_includes Event.awaiting_completion, ended
    refute_includes Event.awaiting_completion, done
    refute_includes Event.awaiting_completion, future
  end

  test "creating an upcoming event auto-reserves users of the currently highest rank only" do
    users(:ala).update!(title:      :master)
    users(:bartek).update!(title:   :veteran)
    users(:cezary).update!(title:   :member)
    users(:dominika).update!(title: :rookie)

    event = Event.create!(valid_attrs(capacity: 4))

    reserved_users = event.participations.reserved.includes(:user).map(&:user)
    # Only ala is master; the rest stay unreserved even though capacity is 4.
    assert_equal [ users(:ala) ], reserved_users
  end

  test "creating an event in the past does not trigger reservations" do
    # Bypass the `ends_at_after_scheduled_at` guard? No — validation still applies.
    # Use a future event that we then manually backdate to simulate a never-upcoming one.
    # Simpler: rely on `upcoming_now?` guard — Event with scheduled_at <= now should not seed.
    event = Event.new(valid_attrs(scheduled_at: 5.minutes.ago, ends_at: 1.hour.from_now))
    event.save!(validate: false)
    event.run_callbacks(:commit)  # no-op guard check

    assert_equal 0, event.participations.reserved.count
  end

  test "full? counts reserved + confirmed against capacity" do
    users(:ala).update!(title: :master)
    event = Event.create!(valid_attrs(capacity: 1))
    assert event.full?, "single reserved slot should mark capacity 1 event as full"
  end

  # --- pre_registered_user_ids -----------------------------------------------
  # Virtual attr set from the event-creation form. Confirmed in-transaction
  # before reservation seeding so pre-registered mistrzowie don't get a separate
  # reservation row.

  test "pre_registered_user_ids confirms users immediately, ahead of reservation seeding" do
    users(:ala).update!(title: :master)  # would otherwise be auto-reserved
    attrs = valid_attrs(capacity: 4, pre_registered_user_ids: [ users(:bartek).id, users(:ala).id ])
    event = Event.create!(attrs)

    confirmed_users = event.participations.confirmed.includes(:user).order(:position).map(&:user)
    assert_includes confirmed_users, users(:ala)
    assert_includes confirmed_users, users(:bartek)
    # Ala is pre-confirmed — not double-booked into a separate `reserved` row.
    assert_equal 0, event.participations.reserved.where(user: users(:ala)).count
  end

  test "pre_registered_user_ids spills onto waitlist when count exceeds capacity" do
    attrs = valid_attrs(
      capacity: 2,
      pre_registered_user_ids: [ users(:ala).id, users(:bartek).id, users(:cezary).id ]
    )
    event = Event.create!(attrs)

    assert_equal 2, event.participations.confirmed.count
    waitlisted = event.participations.waitlist.includes(:user).map(&:user)
    assert_equal [ users(:cezary) ], waitlisted
  end

  test "pre_registered_user_ids skips users blocked by the host" do
    HostBlock.create!(user: users(:bartek), host: hosts(:jan))
    attrs = valid_attrs(capacity: 2, pre_registered_user_ids: [ users(:bartek).id, users(:cezary).id ])
    event = Event.create!(attrs)

    confirmed_users = event.participations.confirmed.includes(:user).map(&:user)
    refute_includes confirmed_users, users(:bartek)
    assert_includes confirmed_users, users(:cezary)
  end

  test "pre_registered_user_ids ignores blank/zero entries (sentinel values)" do
    attrs = valid_attrs(capacity: 4, pre_registered_user_ids: [ "", "0", users(:ala).id.to_s ])
    event = Event.create!(attrs)
    assert_equal [ users(:ala) ], event.participations.confirmed.includes(:user).map(&:user)
  end

  # --- refill_on_capacity_increase -------------------------------------------
  # When a host bumps capacity mid-event we should pull in waitlisters first
  # and only then look at top-tier reservation candidates.

  test "increasing capacity promotes the oldest waitlister into the new slot" do
    # Capacity 1, ala (mistrz) auto-reserves the only slot. Add bartek to waitlist.
    users(:ala).update!(title: :master)
    event = Event.create!(valid_attrs(capacity: 1))
    Participation.create!(event: event, user: users(:bartek), status: :waitlist, position: 1)

    event.update!(capacity: 2)

    bartek = event.participations.find_by(user: users(:bartek))
    assert_equal "confirmed", bartek.status
  end

  test "decreasing capacity is a no-op (does not evict signed-up workers)" do
    users(:ala).update!(title: :master)
    event = Event.create!(valid_attrs(capacity: 4))
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)

    assert_no_difference -> { event.participations.confirmed.count } do
      event.update!(capacity: 2)
    end
  end

  test "updates that don't touch capacity don't trigger any refill" do
    users(:ala).update!(title: :master)
    event = Event.create!(valid_attrs(capacity: 4))
    before = event.participations.holding_slot.count

    event.update!(name: "Inna nazwa")
    assert_equal before, event.participations.holding_slot.count
  end
end
