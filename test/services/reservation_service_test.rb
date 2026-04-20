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

  test "refill_one does NOT cascade down tiers — slot stays open when no top-tier user is available" do
    event = build_event(capacity: 1)
    ReservationService.seed_on_create(event)
    # ala (master) is the sole top-tier user. She declines → cancelled.
    # No other user has title=master, so the slot must stay empty —
    # NOT fall through to bartek (veteran).
    event.participations.reserved.find_by(user: users(:ala))
      .update!(status: :cancelled, reserved_until: nil)

    ReservationService.refill_one(event)

    assert_equal 0, event.participations.reserved.count,
                 "no top-tier user remains; slot must stay open (no cascade)"
    refute event.participations.find_by(user: users(:bartek))&.reserved?,
           "bartek is lower-tier and must not be invited"
  end

  test "refill_one invites another top-tier user when one is still available" do
    # Two users at master. One gets a reservation and cancels; refill_one
    # must invite the OTHER top-tier user (not skip to a lower tier).
    users(:bartek).update!(title: :master)
    event = build_event(capacity: 1)
    ReservationService.seed_on_create(event)

    first = event.participations.reserved.first
    first.update!(status: :cancelled, reserved_until: nil)

    ReservationService.refill_one(event)

    expected_next = [ users(:ala), users(:bartek) ].find { |u| u != first.user }
    assert event.participations.reserved.find_by(user: expected_next),
           "the other top-tier user (#{expected_next.first_name}) should take the vacated slot"
    refute event.participations.find_by(user: users(:cezary))&.reserved?,
           "cezary is lower tier and must not be invited"
  end

  test "refill_one promotes from waitlist FIRST, before inviting a new top-tier candidate" do
    # "jesli nie to wskakuje osoba w kolejce" — a waitlisted user who already raised
    # their hand must beat a never-invited top-rank user.
    users(:bartek).update!(title: :master)  # make bartek a top-tier candidate
    event = build_event(capacity: 2)
    Participation.create!(event: event, user: users(:ala),      status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:cezary),   status: :confirmed, position: 2)
    Participation.create!(event: event, user: users(:dominika), status: :waitlist,  position: 1)
    # Free one confirmed slot.
    event.participations.find_by(user: users(:ala)).update!(status: :cancelled)

    ReservationService.refill_one(event)

    assert_equal "confirmed", event.participations.find_by(user: users(:dominika)).status,
                 "waitlist head must be promoted before a fresh rank invite"
    refute event.participations.find_by(user: users(:bartek))&.reserved?,
           "bartek must NOT be reserved while someone is waiting on the waitlist"
  end

  test "refill_one invites a top-tier candidate when waitlist is empty and one is available" do
    users(:bartek).update!(title: :master)
    event = build_event(capacity: 2)
    Participation.create!(event: event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:cezary), status: :confirmed, position: 2)
    event.participations.find_by(user: users(:ala)).update!(status: :cancelled)

    ReservationService.refill_one(event)

    assert event.participations.reserved.find_by(user: users(:bartek)),
           "with no waitlist, another top-tier user should be invited"
  end

  test "expire_stale! cancels expired reservations and does NOT cascade down tiers" do
    event = build_event(capacity: 1)
    ReservationService.seed_on_create(event)
    ala_res = event.participations.reserved.find_by(user: users(:ala))
    ala_res.update_column(:reserved_until, 5.minutes.ago)

    ReservationService.expire_stale!

    assert event.participations.find_by(user: users(:ala)).cancelled?
    assert_equal 0, event.participations.reserved.count,
                 "no other top-tier user exists; no cascade to lower ranks"
    refute event.participations.find_by(user: users(:bartek))&.reserved?
  end

  test "komendant is top-tier when no master exists" do
    users(:ala).update!(title: :captain)
    users(:ala).managed_hosts << hosts(:jan)

    event = build_event(capacity: 2)
    ReservationService.seed_on_create(event)

    assert_equal :reserved, event.participations.find_by(user: users(:ala))&.status&.to_sym
  end

  test "master wygrywa z komendantem przy seed_on_create" do
    users(:ala).update!(title: :master)
    users(:bartek).update!(title: :captain)
    users(:bartek).managed_hosts << hosts(:jan)

    event = build_event(capacity: 2)
    ReservationService.seed_on_create(event)

    assert_equal :reserved, event.participations.find_by(user: users(:ala))&.status&.to_sym
    assert_nil event.participations.find_by(user: users(:bartek))
  end

  # ---- Capacity increase → waitlist promotion -----------------------------

  # Helper: build an event with N confirmed + M waitlist. Users are created on
  # the fly as simple rookies so the existing fixture ranks don't interfere.
  def event_with_roster(capacity:, confirmed:, waitlist:)
    event = build_event(capacity: capacity)
    confirmed.times do |i|
      u = User.create!(first_name: "C#{i}", last_name: "User", email: "c#{i}@test.example")
      event.participations.create!(user: u, status: :confirmed, position: i + 1)
    end
    waitlist.times do |i|
      u = User.create!(first_name: "W#{i}", last_name: "User", email: "w#{i}@test.example")
      event.participations.create!(user: u, status: :waitlist, position: i + 1)
    end
    event.reload
  end

  test "fill_open_slots promotes oldest waitlister when slot opens up" do
    event = event_with_roster(capacity: 3, confirmed: 3, waitlist: 5)
    event.update_column(:capacity, 4)

    ReservationService.fill_open_slots(event)

    assert_equal 4, event.participations.confirmed.count
    assert_equal 4, event.participations.waitlist.count
    assert_equal "W0 User", event.participations.confirmed.order(:updated_at).last.user.display_name
  end

  test "fill_open_slots promotes multiple waitlisters for larger capacity jump" do
    event = event_with_roster(capacity: 3, confirmed: 3, waitlist: 5)
    event.update_column(:capacity, 6)

    ReservationService.fill_open_slots(event)

    assert_equal 6, event.participations.confirmed.count
    assert_equal 2, event.participations.waitlist.count
  end

  test "fill_open_slots is no-op when event is already full" do
    event = event_with_roster(capacity: 3, confirmed: 3, waitlist: 2)

    assert_no_changes -> { event.participations.confirmed.pluck(:id).sort } do
      ReservationService.fill_open_slots(event)
    end
  end

  test "fill_open_slots is no-op when waitlist is empty and no top-tier fallback available" do
    event = event_with_roster(capacity: 3, confirmed: 2, waitlist: 0)
    event.update_column(:capacity, 5)

    ReservationService.fill_open_slots(event)

    assert_equal 2, event.participations.confirmed.count
    assert_equal 0, event.participations.waitlist.count
  end

  # ---- Event#after_update_commit auto-promotion ---------------------------

  test "increasing event capacity triggers waitlist promotion via callback" do
    event = event_with_roster(capacity: 3, confirmed: 3, waitlist: 5)

    event.update!(capacity: 4)

    assert_equal 4, event.participations.confirmed.count
    assert_equal 4, event.participations.waitlist.count
  end

  test "editing event without capacity change does not touch participations" do
    event = event_with_roster(capacity: 3, confirmed: 3, waitlist: 5)

    event.update!(name: "New name")

    assert_equal 3, event.participations.confirmed.count
    assert_equal 5, event.participations.waitlist.count
  end

  test "decreasing capacity does NOT auto-demote confirmed participants" do
    event = event_with_roster(capacity: 4, confirmed: 4, waitlist: 0)

    event.update!(capacity: 2)

    # Confirmed stays — we intentionally do not evict signed-up workers.
    assert_equal 4, event.participations.confirmed.count
  end
end
