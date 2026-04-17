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

  test "seed_on_create reserves ONLY users of the currently highest rank (no cascade)" do
    event = build_event(capacity: 4)
    ReservationService.seed_on_create(event)

    reserved = event.participations.reserved.includes(:user).order(:position)
    # Only ala is master — she's the lone top-tier user, so only she is reserved,
    # even though capacity is 4. The remaining 3 slots stay open for the regular flow.
    assert_equal 1, reserved.size
    assert_equal users(:ala), reserved.first.user
    assert reserved.first.reserved_until > Time.current
    assert reserved.first.reserved_until <= 1.hour.from_now + 1.second
  end

  test "seed_on_create invites ALL users at the top tier (capped at capacity)" do
    # Two users tied at master — both should get reservations.
    users(:bartek).update!(title: :master)
    event = build_event(capacity: 3)
    ReservationService.seed_on_create(event)

    reserved_users = event.participations.reserved.includes(:user).order(:position).map(&:user)
    assert_equal 2, reserved_users.size
    assert_equal [ users(:ala), users(:bartek) ].sort_by(&:id), reserved_users.sort_by(&:id)
  end

  test "seed_on_create reserves a lone candidate even if the top tier is the default rookie" do
    User.where.not(id: users(:dominika).id).destroy_all  # only rookie remains
    event = build_event(capacity: 3)
    ReservationService.seed_on_create(event)
    assert_equal 1, event.participations.reserved.count
    assert_equal users(:dominika), event.participations.reserved.first.user
  end

  test "seed_on_create enqueues an InvitationMailer + WebPushNotifier per invitee" do
    users(:bartek).update!(title: :master)  # 2 top-tier invitees
    event = build_event(capacity: 3)

    assert_enqueued_emails 2 do
      assert_enqueued_with(job: WebPushNotifier) do
        ReservationService.seed_on_create(event)
      end
    end
  end

  test "refill_one drops one tier at a time when the current top tier is exhausted" do
    event = build_event(capacity: 1)
    ReservationService.seed_on_create(event)
    # ala (master) reserved. She declines → cancelled. Refill should invite the
    # next tier's first user (bartek, veteran), not skip ahead.
    event.participations.reserved.find_by(user: users(:ala))
      .update!(status: :cancelled, reserved_until: nil)

    ReservationService.refill_one(event)

    new_reservation = event.participations.reserved.find_by(user: users(:bartek))
    assert new_reservation, "expected bartek (next tier down) to be invited"
    assert new_reservation.reserved_until > Time.current
  end

  test "refill_one promotes from waitlist FIRST, before inviting a new ranking candidate" do
    # This is the "jesli nie to wskakuje osoba w kolejce" rule: a waitlisted user
    # who already raised their hand must beat a never-invited higher-rank user.
    event = build_event(capacity: 2)
    # Two top-tier confirmed users already in the event. Cezary (veteran)
    # is a candidate available for invite, BUT dominika is waiting on the waitlist.
    Participation.create!(event: event, user: users(:ala),      status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek),   status: :confirmed, position: 2)
    Participation.create!(event: event, user: users(:dominika), status: :waitlist,  position: 1)
    # Free one confirmed slot.
    event.participations.find_by(user: users(:ala)).update!(status: :cancelled)

    ReservationService.refill_one(event)

    assert_equal "confirmed", event.participations.find_by(user: users(:dominika)).status,
                 "waitlist head must be promoted before a fresh rank invite"
    refute event.participations.find_by(user: users(:cezary))&.reserved?,
           "cezary must NOT be reserved while someone is waiting"
  end

  test "refill_one falls back to ranking candidate only when no waitlist exists" do
    event = build_event(capacity: 2)
    # All slots blocked by confirmed users; no waitlist. refill_one must reach
    # for the next ranking candidate (cezary, next tier down).
    Participation.create!(event: event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 2)
    event.participations.find_by(user: users(:ala)).update!(status: :cancelled)

    ReservationService.refill_one(event)

    assert event.participations.reserved.find_by(user: users(:cezary)),
           "with no waitlist, the next-tier user should get a reservation"
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
