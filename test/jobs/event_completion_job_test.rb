require "test_helper"

class EventCompletionJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "marks past events as completed and enqueues notifications for confirmed participants" do
    event = events(:gig-coordinators_tomorrow)
    event.update!(scheduled_at: 3.hours.ago, ends_at: 1.hour.ago)
    u1 = users(:ala); u2 = users(:bartek); u3 = users(:cezary)
    Participation.create!(event: event, user: u1, status: :confirmed, position: 1)
    Participation.create!(event: event, user: u2, status: :confirmed, position: 2)
    Participation.create!(event: event, user: u3, status: :waitlist,  position: 1)

    assert_enqueued_emails 2 do
      EventCompletionJob.perform_now
    end
    assert_not_nil event.reload.completed_at
  end

  test "is idempotent — running twice does not notify again" do
    event = events(:gig-coordinators_tomorrow)
    event.update!(scheduled_at: 3.hours.ago, ends_at: 1.hour.ago)
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)

    EventCompletionJob.perform_now
    assert_enqueued_emails 0 do
      EventCompletionJob.perform_now
    end
  end

  test "does not touch future events" do
    event = events(:gig-coordinators_tomorrow)
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)
    assert_enqueued_emails 0 do
      EventCompletionJob.perform_now
    end
    assert_nil event.reload.completed_at
  end
end
