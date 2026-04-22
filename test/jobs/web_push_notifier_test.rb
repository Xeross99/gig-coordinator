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

  test "fan-out rozdziela się na fazę natychmiastową i 5-min opóźnioną" do
    host = hosts(:jan)
    host.events.create!(name: "Rozjazd", scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
                        pay_per_person: 50, capacity: 2)

    # odsiewamy tylko new_event — seed_reservations osobno enqueue'uje :invitation
    # jobs dla mistrzów_piora, co nie jest przedmiotem tego testu.
    new_event_jobs = enqueued_jobs.select do |j|
      j["job_class"] == "WebPushNotifier" && ActiveJob::Arguments.deserialize(j["arguments"]).first == :new_event
    end
    assert_equal 2, new_event_jobs.size, "oczekujemy 2 fal new_event (natychmiast + opóźniona)"

    immediate = new_event_jobs.find { |j| j["scheduled_at"].blank? }
    delayed   = new_event_jobs.find { |j| j["scheduled_at"].present? }
    assert immediate, "powinien być jeden job natychmiastowy"
    assert delayed,   "powinien być jeden job opóźniony"

    immediate_titles = ActiveJob::Arguments.deserialize(immediate["arguments"]).last[:titles]
    delayed_titles   = ActiveJob::Arguments.deserialize(delayed["arguments"]).last[:titles]
    assert_includes immediate_titles, "master"
    assert_includes immediate_titles, "captain"
    refute_includes immediate_titles, "rookie"
    assert_equal [ "rookie" ], delayed_titles

    # opóźnienie ≈ 5 min (z marginesem 10 s na clock skew)
    delay = Time.zone.parse(delayed["scheduled_at"].to_s) - Time.current
    assert_in_delta Event::NEW_EVENT_LAGGING_DELAY.to_i, delay, 10
  end

  test "delayed wave pomija event, który w międzyczasie został usunięty" do
    host = hosts(:jan)
    event = host.events.create!(name: "Zniknie", scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
                                pay_per_person: 50, capacity: 2)
    # żółtodziob z subskrypcją push — normalnie dostałby pinga po 5 min
    bartek = users(:bartek)
    bartek.update!(title: :rookie)
    PushSubscription.create!(user: bartek, endpoint: "https://example.com/push/1",
                             p256dh_key: "p", auth_key: "a")

    event.destroy

    assert_nothing_raised do
      WebPushNotifier.new.perform(:new_event, event_id: event.id, titles: %w[rookie])
    end
  end

  test "delayed wave filtruje subskrypcje do rangi żółtodzioba" do
    host   = hosts(:jan)
    event  = host.events.create!(name: "Filtr", scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
                                 pay_per_person: 50, capacity: 2)

    zoltek  = users(:bartek); zoltek.update!(title: :rookie)
    mistrz  = users(:cezary); mistrz.update!(title: :master)

    sub_z = PushSubscription.create!(user: zoltek, endpoint: "https://example.com/push/z",
                                     p256dh_key: "p", auth_key: "a")
    sub_m = PushSubscription.create!(user: mistrz, endpoint: "https://example.com/push/m",
                                     p256dh_key: "p", auth_key: "a")

    sent = []
    job  = WebPushNotifier.new
    job.define_singleton_method(:send_web_push) { |sub, _payload| sent << sub.id }

    job.perform(:new_event, event_id: event.id, titles: %w[rookie])
    assert_equal [ sub_z.id ], sent, "tylko subskrypcja żółtodzioba powinna dostać push w fali opóźnionej"

    sent.clear
    immediate_titles = User.titles.keys - [ "rookie" ]
    job.perform(:new_event, event_id: event.id, titles: immediate_titles)
    assert_equal [ sub_m.id ], sent, "fala natychmiastowa pomija żółtodziobów"
  end
end
