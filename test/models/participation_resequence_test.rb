require "test_helper"

class ParticipationResequenceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @host = hosts(:jan)
    @event = build_event(capacity: 6)
  end

  def build_event(capacity:)
    event = Event.create!(
      host: @host, name: "Resequence test",
      scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
      pay_per_person: 100, capacity: capacity
    )
    event.participations.destroy_all
    event
  end

  def add_users(event, status:, count:, starting_position: 1)
    count.times.map do |i|
      pos = starting_position + i
      u = User.create!(first_name: "#{status}#{pos}", last_name: "U", email: "#{status}#{pos}_#{event.id}@test.example")
      Participation.create!(event: event, user: u, status: status, position: pos)
    end
  end

  def positions_for(event, status)
    event.participations.where(status: status).order(:position).pluck(:position)
  end

  # --- resequence! unit tests ---

  test "resequence! compacts gaps in waitlist positions" do
    w1 = add_users(@event, status: :waitlist, count: 1, starting_position: 3).first
    w2 = add_users(@event, status: :waitlist, count: 1, starting_position: 7).first
    w3 = add_users(@event, status: :waitlist, count: 1, starting_position: 12).first

    Participation.resequence!(@event, :waitlist)

    assert_equal [ 1, 2, 3 ], positions_for(@event, :waitlist)
    assert_equal 1, w1.reload.position
    assert_equal 2, w2.reload.position
    assert_equal 3, w3.reload.position
  end

  test "resequence! compacts gaps in confirmed positions" do
    c1 = add_users(@event, status: :confirmed, count: 1, starting_position: 1).first
    c2 = add_users(@event, status: :confirmed, count: 1, starting_position: 5).first
    c3 = add_users(@event, status: :confirmed, count: 1, starting_position: 9).first

    Participation.resequence!(@event, :confirmed)

    assert_equal [ 1, 2, 3 ], positions_for(@event, :confirmed)
    assert_equal 1, c1.reload.position
    assert_equal 2, c2.reload.position
    assert_equal 3, c3.reload.position
  end

  test "resequence! preserves relative order" do
    w1 = add_users(@event, status: :waitlist, count: 1, starting_position: 5).first
    w2 = add_users(@event, status: :waitlist, count: 1, starting_position: 2).first
    w3 = add_users(@event, status: :waitlist, count: 1, starting_position: 8).first

    Participation.resequence!(@event, :waitlist)

    ordered_ids = @event.participations.waitlist.order(:position).pluck(:id)
    assert_equal [ w2.id, w1.id, w3.id ], ordered_ids
    assert_equal [ 1, 2, 3 ], positions_for(@event, :waitlist)
  end

  test "resequence! is a no-op when positions are already contiguous" do
    add_users(@event, status: :waitlist, count: 3, starting_position: 1)

    assert_no_changes -> { positions_for(@event, :waitlist) } do
      Participation.resequence!(@event, :waitlist)
    end
  end

  test "resequence! handles empty list" do
    assert_nothing_raised do
      Participation.resequence!(@event, :waitlist)
    end
  end

  test "resequence! handles single item with wrong position" do
    w = add_users(@event, status: :waitlist, count: 1, starting_position: 42).first

    Participation.resequence!(@event, :waitlist)

    assert_equal 1, w.reload.position
  end

  test "resequence! does not affect other statuses" do
    add_users(@event, status: :confirmed, count: 2, starting_position: 5)
    add_users(@event, status: :waitlist, count: 2, starting_position: 10)

    Participation.resequence!(@event, :waitlist)

    assert_equal [ 5, 6 ], positions_for(@event, :confirmed)
    assert_equal [ 1, 2 ], positions_for(@event, :waitlist)
  end

  test "resequence! does not trigger model callbacks (uses update_column)" do
    add_users(@event, status: :waitlist, count: 2, starting_position: 5)

    assert_no_enqueued_jobs do
      Participation.resequence!(@event, :waitlist)
    end
  end

  # --- Integration: cancel confirmed → positions stay contiguous ---

  # Goły `update!(status: :cancelled)` — bez ręcznego promote/resequence —
  # musi zostawić spójny roster; promocję i resequence robi callback modelu
  # (refill_after_cancellation). To jest kontrakt „działa z konsoli".
  test "canceling a confirmed user promotes a waitlister and leaves contiguous positions" do
    confirmed = add_users(@event, status: :confirmed, count: 4, starting_position: 1)
    waitlist = add_users(@event, status: :waitlist, count: 5, starting_position: 1)

    confirmed[1].update!(status: :cancelled)

    assert_equal (1..4).to_a, positions_for(@event, :confirmed)
    assert_equal (1..4).to_a, positions_for(@event, :waitlist)
    assert waitlist.first.reload.confirmed?, "oldest waitlister must be auto-promoted"
  end

  test "canceling multiple confirmed users promotes waitlisters and leaves contiguous positions" do
    confirmed = add_users(@event, status: :confirmed, count: 5, starting_position: 1)
    waitlist = add_users(@event, status: :waitlist, count: 3, starting_position: 1)

    confirmed[0].update!(status: :cancelled)
    confirmed[2].update!(status: :cancelled)
    confirmed[4].update!(status: :cancelled)

    # Każdy cancel promuje jednego waitlistera — 3 cancels, 3 promocje.
    assert_equal [ 1, 2, 3, 4, 5 ], positions_for(@event, :confirmed)
    assert_equal [], positions_for(@event, :waitlist)
    assert waitlist.all? { |w| w.reload.confirmed? }
  end

  test "canceling a waitlist user leaves contiguous waitlist positions" do
    add_users(@event, status: :confirmed, count: 4, starting_position: 1)
    waitlist = add_users(@event, status: :waitlist, count: 5, starting_position: 1)

    waitlist[2].update!(status: :cancelled)

    assert_equal (1..4).to_a, positions_for(@event, :waitlist)
    remaining_user_ids = @event.participations.waitlist.order(:position).pluck(:user_id)
    assert_equal [ waitlist[0], waitlist[1], waitlist[3], waitlist[4] ].map(&:user_id), remaining_user_ids
  end

  test "promotion from waitlist resequences waitlist" do
    add_users(@event, status: :confirmed, count: 3, starting_position: 1)
    waitlist = add_users(@event, status: :waitlist, count: 4, starting_position: 1)

    ReservationService.promote_from_waitlist(@event)

    assert_equal (1..3).to_a, positions_for(@event, :waitlist)
    ordered_users = @event.participations.waitlist.order(:position).map(&:user)
    assert_equal [ waitlist[1].user, waitlist[2].user, waitlist[3].user ], ordered_users
  end

  test "repeated promotions maintain contiguous positions" do
    add_users(@event, status: :confirmed, count: 2, starting_position: 1)
    waitlist = add_users(@event, status: :waitlist, count: 5, starting_position: 1)

    3.times { ReservationService.promote_from_waitlist(@event) }

    assert_equal (1..2).to_a, positions_for(@event, :waitlist)
    assert_equal (1..5).to_a, positions_for(@event, :confirmed)
  end

  # --- Stress test: alternating joins and cancels ---

  test "positions stay contiguous after a complex sequence of joins and cancels" do
    users_pool = 10.times.map do |i|
      User.create!(first_name: "Pool#{i}", last_name: "U", email: "pool#{i}@test.example")
    end

    users_pool[0..5].each_with_index do |u, i|
      status = i < @event.capacity ? :confirmed : :waitlist
      pos = if status == :confirmed
        (@event.participations.confirmed.maximum(:position) || 0) + 1
      else
        (@event.participations.waitlist.maximum(:position) || 0) + 1
      end
      @event.participations.create!(user: u, status: status, position: pos)
    end

    Event.transaction do
      @event.lock!
      @event.participations.confirmed.order(:position).limit(2).each { |p| p.update!(status: :cancelled) }
      2.times do
        promoted = @event.participations.waitlist.order(:position).first
        break unless promoted
        pos = (@event.participations.confirmed.maximum(:position) || 0) + 1
        promoted.update!(status: :confirmed, position: pos)
      end
      Participation.resequence!(@event, :confirmed)
      Participation.resequence!(@event, :waitlist)
    end

    confirmed_positions = positions_for(@event, :confirmed)
    waitlist_positions = positions_for(@event, :waitlist)
    assert_equal (1..confirmed_positions.size).to_a, confirmed_positions
    assert_equal (1..waitlist_positions.size).to_a, waitlist_positions
  end
end
