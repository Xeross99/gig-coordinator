require "test_helper"

class ReservationExpirationJobTest < ActiveJob::TestCase
  setup do
    @host = hosts(:jan)
    users(:ala).update!(title:    :master)
    users(:bartek).update!(title: :master)
    users(:cezary).update!(title: :veteran)
  end

  test "perform cancels expired reservations and hands the slot to another top-tier user" do
    event = Event.create!(
      host: @host, name: "Test", capacity: 1,
      scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
      pay_per_person: 100
    )
    initial_res = event.participations.reserved.first
    assert initial_res, "setup: after_create_commit should reserve one of the two top-tier users"
    initial_res.update_column(:reserved_until, 2.minutes.ago)

    ReservationExpirationJob.perform_now

    assert initial_res.reload.cancelled?
    other_top = [ users(:ala), users(:bartek) ].find { |u| u != initial_res.user }
    assert event.participations.reserved.find_by(user: other_top),
           "the other top-tier user (#{other_top.first_name}) should inherit the slot"
    refute event.participations.find_by(user: users(:cezary))&.reserved?,
           "cezary is lower-tier and must not be invited (no cascade)"
  end
end
