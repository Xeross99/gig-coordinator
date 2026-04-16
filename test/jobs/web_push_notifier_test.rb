require "test_helper"

class WebPushNotifierTest < ActiveJob::TestCase
  test "enqueued on event creation when event is upcoming" do
    host = hosts(:jan)
    assert_enqueued_with(job: WebPushNotifier) do
      host.events.create!(name: "Nowy", scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
                          pay_per_person: 50, capacity: 2)
    end
  end

  test "not enqueued for past events" do
    host = hosts(:jan)
    assert_no_enqueued_jobs only: WebPushNotifier do
      host.events.create!(name: "Stary", scheduled_at: 2.days.ago, ends_at: 2.days.ago + 1.hour,
                          pay_per_person: 50, capacity: 2)
    end
  end
end
