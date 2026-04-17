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
end
