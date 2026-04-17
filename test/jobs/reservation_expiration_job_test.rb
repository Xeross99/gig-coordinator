require "test_helper"

class ReservationExpirationJobTest < ActiveJob::TestCase
  setup do
    @host = hosts(:jan)
    users(:ala).update!(title: :master)
    users(:bartek).update!(title: :veteran)
  end

  test "perform cancels expired reservations and hands the slot to the next rank" do
    event = Event.create!(
      host: @host, name: "Test", capacity: 1,
      scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
      pay_per_person: 100
    )
    # Expect ala reserved by the after_create_commit hook.
    ala_res = event.participations.reserved.find_by(user: users(:ala))
    assert ala_res, "setup precondition: ala should be reserved"
    ala_res.update_column(:reserved_until, 2.minutes.ago)

    ReservationExpirationJob.perform_now

    assert event.participations.find_by(user: users(:ala)).cancelled?
    assert event.participations.reserved.find_by(user: users(:bartek)),
           "bartek (next rank) should inherit the slot"
  end
end
