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
    assert_includes immediate_titles, "mistrz_piora"
    assert_includes immediate_titles, "kurnikowy_komendant"
    assert_includes immediate_titles, "kurnikowy_gangster"
    refute_includes immediate_titles, "zoltodziob",     "żółtodziób ma być całkowicie pominięty"
    refute_includes immediate_titles, "kurzy_pacholek", "pachołek leci dopiero w fali opóźnionej"
    assert_equal [ "kurzy_pacholek" ], delayed_titles

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
    bartek.update!(title: :zoltodziob)
    PushSubscription.create!(user: bartek, endpoint: "https://example.com/push/1",
                             p256dh_key: "p", auth_key: "a")

    event.destroy

    assert_nothing_raised do
      WebPushNotifier.new.perform(:new_event, event_id: event.id, titles: %w[zoltodziob])
    end
  end

  test "delayed wave filtruje subskrypcje do rangi pachołka" do
    host   = hosts(:jan)
    event  = host.events.create!(name: "Filtr", scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
                                 pay_per_person: 50, capacity: 2)

    zoltek   = users(:ala);     zoltek.update!(title:   :zoltodziob)
    pacholek = users(:bartek);  pacholek.update!(title: :kurzy_pacholek)
    mistrz   = users(:cezary);  mistrz.update!(title:   :mistrz_piora)

    sub_z = PushSubscription.create!(user: zoltek,   endpoint: "https://example.com/push/z",
                                     p256dh_key: "p", auth_key: "a")
    sub_p = PushSubscription.create!(user: pacholek, endpoint: "https://example.com/push/p",
                                     p256dh_key: "p", auth_key: "a")
    sub_m = PushSubscription.create!(user: mistrz,   endpoint: "https://example.com/push/m",
                                     p256dh_key: "p", auth_key: "a")

    sent = []
    job  = WebPushNotifier.new
    job.define_singleton_method(:send_web_push) { |sub, _payload| sent << sub.id }

    job.perform(:new_event, event_id: event.id, titles: Event::NEW_EVENT_LAGGING_TITLES)
    assert_equal [ sub_p.id ], sent, "fala opóźniona idzie tylko do pachołków"

    sent.clear
    immediate_titles = User.titles.keys - Event::NEW_EVENT_LAGGING_TITLES - Event::NEW_EVENT_EXCLUDED_TITLES
    job.perform(:new_event, event_id: event.id, titles: immediate_titles)
    assert_equal [ sub_m.id ], sent, "fala natychmiastowa pomija żółtodziobów i pachołków"
  end

  # --- :event_changed -----------------------------------------------------------

  test ":event_changed sends push to all users with subscriptions" do
    host  = hosts(:jan)
    event = host.events.create!(name: "Zmiana", scheduled_at: 1.day.from_now,
                                ends_at: 1.day.from_now + 2.hours, pay_per_person: 50, capacity: 4)
    event.participations.destroy_all

    confirmed_user = users(:ala)
    waitlist_user  = users(:bartek)
    no_part_user   = users(:cezary)

    Participation.create!(event: event, user: confirmed_user, status: :confirmed, position: 1)
    Participation.create!(event: event, user: waitlist_user,  status: :waitlist,  position: 1)

    sub_confirmed = PushSubscription.create!(user: confirmed_user, endpoint: "https://example.com/push/c",
                                             p256dh_key: "p", auth_key: "a")
    sub_waitlist  = PushSubscription.create!(user: waitlist_user,  endpoint: "https://example.com/push/w",
                                             p256dh_key: "p", auth_key: "a")
    sub_no_part   = PushSubscription.create!(user: no_part_user,   endpoint: "https://example.com/push/n",
                                             p256dh_key: "p", auth_key: "a")

    sent = []
    job  = WebPushNotifier.new
    job.define_singleton_method(:send_web_push) { |sub, _payload| sent << sub.id }

    job.perform(:event_changed, event_id: event.id, changed_fields: %w[scheduled_at])

    assert_includes sent, sub_confirmed.id, "confirmed powinien dostać pusha"
    assert_includes sent, sub_waitlist.id,  "waitlist powinien dostać pusha"
    assert_includes sent, sub_no_part.id,   "user bez udziału powinien dostać pusha"
  end

  test ":event_changed payload contains changed field labels in Polish" do
    host  = hosts(:jan)
    event = host.events.create!(name: "Test payload", scheduled_at: 1.day.from_now,
                                ends_at: 1.day.from_now + 2.hours, pay_per_person: 50, capacity: 4)

    payloads = []
    job = WebPushNotifier.new
    job.define_singleton_method(:send_web_push) { |_sub, payload| payloads << payload }

    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)
    PushSubscription.create!(user: users(:ala), endpoint: "https://example.com/push/x",
                             p256dh_key: "p", auth_key: "a")

    job.perform(:event_changed, event_id: event.id, changed_fields: %w[scheduled_at pay_per_person])

    payload = payloads.first
    assert_equal "Zmiana w Test payload", payload[:title]
    assert_includes payload[:body], "datę startu"
    assert_includes payload[:body], "stawkę"
  end

  test ":event_changed skips if event was deleted before job runs" do
    assert_nothing_raised do
      WebPushNotifier.new.perform(:event_changed, event_id: -1, changed_fields: %w[capacity])
    end
  end

  test "żółtodziób NIGDY nie dostaje pusha o nowym evencie (ani natychmiastowo, ani z opóźnieniem)" do
    host  = hosts(:jan)
    event = host.events.create!(name: "Brak pusha", scheduled_at: 1.day.from_now,
                                ends_at: 1.day.from_now + 2.hours, pay_per_person: 50, capacity: 2)

    zoltek = users(:ala); zoltek.update!(title: :zoltodziob)
    PushSubscription.create!(user: zoltek, endpoint: "https://example.com/push/zoltek",
                             p256dh_key: "p", auth_key: "a")

    sent = []
    job  = WebPushNotifier.new
    job.define_singleton_method(:send_web_push) { |sub, _payload| sent << sub.id }

    # Symulujemy obie fale tak, jak Event.notify_new_event_subscribers je odpala.
    immediate_titles = User.titles.keys - Event::NEW_EVENT_LAGGING_TITLES - Event::NEW_EVENT_EXCLUDED_TITLES
    job.perform(:new_event, event_id: event.id, titles: immediate_titles)
    job.perform(:new_event, event_id: event.id, titles: Event::NEW_EVENT_LAGGING_TITLES)

    assert_empty sent, "żaden push o nowym evencie nie powinien trafić do żółtodzioba"
  end
end
