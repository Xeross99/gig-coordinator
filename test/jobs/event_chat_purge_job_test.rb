require "test_helper"

class EventChatPurgeJobTest < ActiveJob::TestCase
  test "deletes all messages for a started event" do
    event = events(:gig-coordinators_tomorrow)
    event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    Message.create!(event: event, user: users(:ala),    body: "pierwsza")
    Message.create!(event: event, user: users(:bartek), body: "druga")

    assert_difference -> { event.messages.count }, -2 do
      EventChatPurgeJob.perform_now(event.id)
    end
  end

  test "is a no-op when event has no messages" do
    event = events(:gig-coordinators_tomorrow)
    event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)

    assert_nothing_raised { EventChatPurgeJob.perform_now(event.id) }
    assert_equal 0, event.messages.count
  end

  test "re-enqueues itself when event has not started yet (scheduled_at moved later)" do
    event = events(:gig-coordinators_tomorrow)
    Message.create!(event: event, user: users(:ala), body: "early")
    refute event.started?

    assert_enqueued_with(job: EventChatPurgeJob) do
      EventChatPurgeJob.perform_now(event.id)
    end
    assert_equal 1, event.messages.count, "messages must survive when event not started yet"
  end

  test "is a no-op when event has been deleted" do
    assert_nothing_raised { EventChatPurgeJob.perform_now(999_999) }
  end
end
