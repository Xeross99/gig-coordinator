require "test_helper"

class ParticipationEventTest < ActiveSupport::TestCase
  setup do
    @event = events(:gig_coordinators_tomorrow)
    @user  = users(:ala)
  end

  test "enum event_types mapping" do
    assert_equal(
      { "joined" => 0, "cancelled" => 1, "reserved" => 2, "accepted" => 3,
        "declined" => 4, "promoted" => 5, "expired" => 6 },
      ParticipationEvent.event_types
    )
  end

  test "participation is required" do
    pe = ParticipationEvent.new(event_type: :joined)
    refute pe.valid?
    assert pe.errors[:participation].any?
  end

  test "destroying participation deletes its participation_events (dependent: :delete_all)" do
    p = Participation.create!(event: @event, user: @user, status: :confirmed, position: 1)
    # create! już nagrał :joined przez after_commit na Participation
    assert_equal 1, p.participation_events.count
    ids = p.participation_events.pluck(:id)

    p.destroy

    assert_equal 0, ParticipationEvent.where(id: ids).count,
                 "participation_events dla usuniętego rekordu muszą zniknąć"
  end
end
