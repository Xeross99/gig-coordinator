require "test_helper"

# Regresja: `message_json` było memoizowane na instancji joba
# (`@message_json ||= payload.to_json`), a kindy :event_reminder
# i :carpool_departed wysyłają w jednym perform RÓŻNE, spersonalizowane
# payloady per odbiorca — każdy web-pushowy odbiorca po pierwszym dostawał
# więc treść pierwszego odbiorcy.
class WebPushNotifierPayloadTest < ActiveJob::TestCase
  test "message_json zwraca świeży JSON dla każdego payloadu (bez memoizacji)" do
    job = WebPushNotifier.new

    assert_equal({ a: 1 }.to_json, job.send(:message_json, { a: 1 }))
    assert_equal({ b: 2 }.to_json, job.send(:message_json, { b: 2 }),
                 "drugie wywołanie nie może zwrócić zmemoizowanego JSON-a pierwszego payloadu")
  end

  test ":event_reminder dostarcza każdemu odbiorcy jego własny, spersonalizowany JSON" do
    host  = hosts(:jan)
    event = host.events.create!(name: "Przypominajka", scheduled_at: 1.day.from_now,
                                ends_at: 1.day.from_now + 2.hours, pay_per_person: 50, capacity: 4)

    ala    = users(:ala)
    bartek = users(:bartek)
    Participation.create!(event: event, user: ala,    status: :confirmed, position: 1)
    Participation.create!(event: event, user: bartek, status: :confirmed, position: 2)
    PushSubscription.create!(user: ala,    endpoint: "https://example.com/push/reminder-a",
                             p256dh_key: "p", auth_key: "a")
    PushSubscription.create!(user: bartek, endpoint: "https://example.com/push/reminder-b",
                             p256dh_key: "p", auth_key: "a")

    bodies = Concurrent::Array.new
    job = WebPushNotifier.new
    job.define_singleton_method(:send_web_push) do |_sub, payload, **|
      bodies << message_json(payload)
    end

    job.perform(:event_reminder, event_id: event.id)

    assert_equal 2, bodies.size
    assert_equal 2, bodies.uniq.size,
                 "każdy odbiorca dostaje własny JSON — nie kopię body pierwszego odbiorcy"
    assert bodies.any? { |b| b.include?("Ala") },    "spersonalizowane body dla Ali"
    assert bodies.any? { |b| b.include?("Bartek") }, "spersonalizowane body dla Bartka"
  end
end
