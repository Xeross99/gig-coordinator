require "test_helper"

class EventCompletionJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  test "marks past events as completed and enqueues one push notification per confirmed participant" do
    event = events(:gig_coordinators_tomorrow)
    event.update!(scheduled_at: 3.hours.ago, ends_at: 1.hour.ago)
    u1 = users(:ala); u2 = users(:bartek); u3 = users(:cezary)
    Participation.create!(event: event, user: u1, status: :confirmed, position: 1)
    Participation.create!(event: event, user: u2, status: :confirmed, position: 2)
    Participation.create!(event: event, user: u3, status: :waitlist,  position: 1)

    assert_enqueued_with(job: WebPushNotifier) do
      EventCompletionJob.perform_now
    end
    assert_equal 2, ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j[:job] == WebPushNotifier }
    assert_not_nil event.reload.completed_at
  end

  test "is idempotent — running twice does not re-notify" do
    event = events(:gig_coordinators_tomorrow)
    event.update!(scheduled_at: 3.hours.ago, ends_at: 1.hour.ago)
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)

    EventCompletionJob.perform_now
    before = ActiveJob::Base.queue_adapter.enqueued_jobs.count
    EventCompletionJob.perform_now
    assert_equal before, ActiveJob::Base.queue_adapter.enqueued_jobs.count
  end

  test "does not touch future events" do
    event = events(:gig_coordinators_tomorrow)
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)
    EventCompletionJob.perform_now
    assert_nil event.reload.completed_at
    refute ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |j| j[:job] == WebPushNotifier }
  end
end
