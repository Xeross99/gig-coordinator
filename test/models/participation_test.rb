require "test_helper"

class ParticipationTest < ActiveSupport::TestCase
  setup do
    @event = events(:gig-coordinators_tomorrow) # capacity: 4
    @user  = users(:ala)
  end

  test "can be created with confirmed status" do
    p = Participation.new(event: @event, user: @user, status: :confirmed, position: 1)
    assert p.valid?
  end

  test "enum statuses" do
    assert_equal ({ "confirmed" => 0, "waitlist" => 1, "cancelled" => 2, "reserved" => 3 }), Participation.statuses
  end

  test "reservation_expired? is true only for reserved participations past their deadline" do
    p = Participation.new(status: :reserved, reserved_until: 1.hour.ago)
    assert p.reservation_expired?
    p.reserved_until = 1.hour.from_now
    refute p.reservation_expired?
    p.status = :confirmed
    refute p.reservation_expired?
  end

  test "scope :holding_slot includes confirmed + reserved, excludes waitlist + cancelled" do
    confirmed = Participation.create!(event: @event, user: users(:ala),     status: :confirmed, position: 1)
    reserved  = Participation.create!(event: @event, user: users(:bartek),  status: :reserved,  position: 1,
                                      reserved_until: 1.hour.from_now)
    waitlist  = Participation.create!(event: @event, user: users(:cezary),  status: :waitlist,  position: 1)
    cancelled = Participation.create!(event: @event, user: users(:dominika),status: :cancelled, position: 0)

    held = @event.participations.holding_slot
    assert_includes held, confirmed
    assert_includes held, reserved
    refute_includes held, waitlist
    refute_includes held, cancelled
  end

  test "user cannot participate twice in same event" do
    Participation.create!(event: @event, user: @user, status: :confirmed, position: 1)
    dup = Participation.new(event: @event, user: @user, status: :waitlist, position: 1)
    refute dup.valid?
    assert dup.errors[:user_id].any?
  end

  test "scope :active excludes cancelled" do
    p_confirmed = Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    p_waitlist  = Participation.create!(event: @event, user: users(:bartek), status: :waitlist, position: 1)
    p_cancel    = Participation.create!(event: @event, user: users(:cezary), status: :cancelled, position: 1)
    active = @event.participations.active
    assert_includes active, p_confirmed
    assert_includes active, p_waitlist
    refute_includes active, p_cancel
  end
end
