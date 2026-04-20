require "test_helper"

class ParticipationPromotionTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:gig-coordinators_tomorrow) # capacity: 4
  end

  def fill_event_and_queue_waitlist(waitlist_size: 2)
    confirmed = 4.times.map do |i|
      u = User.create!(first_name: "Confirmed#{i}", last_name: "Conf#{i}", email: "c#{i}@example.com")
      Participation.create!(event: @event, user: u, status: :confirmed, position: i + 1)
    end
    waitlist = waitlist_size.times.map do |i|
      u = User.create!(first_name: "Waiter#{i}", last_name: "Wait#{i}", email: "w#{i}@example.com")
      Participation.create!(event: @event, user: u, status: :waitlist, position: i + 1)
    end
    [ confirmed, waitlist ]
  end

  test "canceling a confirmed participation promotes the oldest waitlist person" do
    confirmed, waitlist = fill_event_and_queue_waitlist

    sign_in_as(confirmed.first.user)
    delete event_participation_path(@event)

    assert confirmed.first.reload.cancelled?
    assert waitlist.first.reload.confirmed?
    assert waitlist.last.reload.waitlist?

    # Capacity stays filled
    assert_equal 4, @event.participations.confirmed.count
  end

  test "canceling a waitlist participation does not trigger promotion" do
    confirmed, waitlist = fill_event_and_queue_waitlist

    sign_in_as(waitlist.first.user)
    delete event_participation_path(@event)

    assert waitlist.first.reload.cancelled?
    # Other waitlist stays waitlist
    assert waitlist.last.reload.waitlist?
    # Confirmed still the same 4
    assert_equal 4, @event.participations.confirmed.count
  end

  test "canceling confirmed when waitlist is empty leaves a free spot" do
    confirmed, _ = fill_event_and_queue_waitlist(waitlist_size: 0)

    sign_in_as(confirmed.first.user)
    delete event_participation_path(@event)

    assert_equal 3, @event.participations.confirmed.count
    assert_equal 0, @event.participations.waitlist.count
  end

  test "promotion assigns next confirmed position" do
    confirmed, waitlist = fill_event_and_queue_waitlist
    max_pos = @event.participations.confirmed.maximum(:position)

    sign_in_as(confirmed.first.user)
    delete event_participation_path(@event)

    promoted = waitlist.first.reload
    assert_equal max_pos + 1, promoted.position
  end
end
