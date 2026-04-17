require "test_helper"

class ReservationServiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @host = hosts(:jan)
    # Give fixtures distinct titles so ranking is deterministic.
    users(:ala).update!(title:     :master)        # rank 3
    users(:bartek).update!(title:  :veteran)  # rank 2
    users(:cezary).update!(title:  :member)      # rank 1
    users(:dominika).update!(title: :rookie)         # rank 0
  end

  # Create an event and wipe auto-seeded reservations (from the `after_create_commit`
  # callback) so each test drives the service explicitly from a clean state.
  def build_event(capacity:)
    event = Event.create!(
      host: @host, name: "Test",
      scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
      pay_per_person: 100, capacity: capacity
    )
    event.participations.destroy_all
    ActionMailer::Base.deliveries.clear
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    event
  end

  test "seed_on_create reserves the top N users ordered by title desc" do
    event = build_event(capacity: 2)
    ReservationService.seed_on_create(event)

    reserved = event.participations.reserved.includes(:user).order(:position)
    assert_equal 2, reserved.size
    assert_equal [ users(:ala), users(:bartek) ], reserved.map(&:user)
    reserved.each do |p|
      assert p.reserved_until > Time.current
      assert p.reserved_until <= 1.hour.from_now + 1.second
    end
  end

  test "seed_on_create reserves fewer slots when candidate pool is smaller than capacity" do
    User.where.not(id: users(:ala).id).destroy_all
    event = build_event(capacity: 5)
    ReservationService.seed_on_create(event)
    assert_equal 1, event.participations.reserved.count
    assert_equal users(:ala), event.participations.reserved.first.user
  end

  test "seed_on_create enqueues an InvitationMailer + WebPushNotifier per invitee" do
    event = build_event(capacity: 2)

    assert_enqueued_emails 2 do
      assert_enqueued_with(job: WebPushNotifier) do
        ReservationService.seed_on_create(event)
      end
    end
  end

  test "refill_one invites the next highest-rank user not already in the event" do
    event = build_event(capacity: 2)
    ReservationService.seed_on_create(event)
    # ala + bartek reserved. bartek declines → controller cancels. refill_one should invite cezary.
    event.participations.reserved.find_by(user: users(:bartek))
      .update!(status: :cancelled, reserved_until: nil)

    ReservationService.refill_one(event)

    new_reservation = event.participations.reserved.find_by(user: users(:cezary))
    assert new_reservation, "expected cezary to be invited as next in rank"
    assert new_reservation.reserved_until > Time.current
  end

  test "refill_one falls back to promoting from waitlist when the ranking pool is exhausted" do
    event = build_event(capacity: 2)
    # All users already in the event — no ranking candidates remain.
    Participation.create!(event: event, user: users(:ala),      status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek),   status: :confirmed, position: 2)
    Participation.create!(event: event, user: users(:cezary),   status: :waitlist,  position: 1)
    Participation.create!(event: event, user: users(:dominika), status: :waitlist,  position: 2)

    # Free one confirmed slot.
    event.participations.find_by(user: users(:ala)).update!(status: :cancelled)

    ReservationService.refill_one(event)

    assert_equal "confirmed", event.participations.find_by(user: users(:cezary)).status,
                 "waitlist head should be promoted when no ranking candidates remain"
  end

  test "expire_stale! cancels expired reservations and refills" do
    event = build_event(capacity: 1)
    ReservationService.seed_on_create(event)
    ala_res = event.participations.reserved.find_by(user: users(:ala))
    # Manually backdate the reservation so it is expired.
    ala_res.update_column(:reserved_until, 5.minutes.ago)

    ReservationService.expire_stale!

    assert event.participations.find_by(user: users(:ala)).cancelled?
    assert event.participations.reserved.find_by(user: users(:bartek)),
           "next rank user (bartek) should be invited after ala's expiry"
  end
end
