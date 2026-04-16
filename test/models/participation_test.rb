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
    assert_equal ({ "confirmed" => 0, "waitlist" => 1, "cancelled" => 2 }), Participation.statuses
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
