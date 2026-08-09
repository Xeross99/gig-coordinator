require "test_helper"

class EventTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def valid_attrs(overrides = {})
    {
      host: hosts(:jan),
      name: "Lapanie kur",
      scheduled_at: 2.days.from_now,
      ends_at: 2.days.from_now + 3.hours,
      pay_per_person: 150.0,
      capacity: 4
    }.merge(overrides)
  end

  test "valid event can be created" do
    assert Event.new(valid_attrs).valid?
  end

  test "requires name, scheduled_at, ends_at, pay_per_person, capacity, host" do
    e = Event.new
    refute e.valid?
    %i[name scheduled_at ends_at pay_per_person capacity host].each do |attr|
      assert e.errors[attr].any?, "expected errors on #{attr}"
    end
  end

  test "capacity must be positive integer" do
    refute Event.new(valid_attrs(capacity: 0)).valid?
    refute Event.new(valid_attrs(capacity: -1)).valid?
  end

  test "pay_per_person must be non-negative" do
    refute Event.new(valid_attrs(pay_per_person: -1)).valid?
    assert Event.new(valid_attrs(pay_per_person: 0)).valid?
  end

  test "ends_at must be after scheduled_at" do
    e = Event.new(valid_attrs(scheduled_at: 2.days.from_now, ends_at: 1.day.from_now))
    refute e.valid?
    assert e.errors[:ends_at].any?
  end

  test "scope :upcoming returns future events ordered by scheduled_at" do
    Event.delete_all
    past  = Event.create!(valid_attrs(scheduled_at: 3.days.ago,   ends_at: 3.days.ago + 2.hours, name: "past"))
    soon  = Event.create!(valid_attrs(scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours, name: "soon"))
    later = Event.create!(valid_attrs(scheduled_at: 5.days.from_now, ends_at: 5.days.from_now + 2.hours, name: "later"))
    assert_equal [ soon, later ], Event.upcoming.to_a
    refute_includes Event.upcoming, past
  end

  test "started? is false when scheduled_at is in the future" do
    e = Event.new(valid_attrs(scheduled_at: 1.hour.from_now))
    refute e.started?
  end

  test "started? is true when scheduled_at has passed" do
    e = Event.new(valid_attrs(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now))
    assert e.started?
  end

  test "started? is true when scheduled_at equals now (boundary uses <=)" do
    frozen = Time.zone.local(2030, 6, 1, 12, 0, 0)
    e = Event.new(valid_attrs(scheduled_at: frozen, ends_at: frozen + 1.hour))
    travel_to(frozen) do
      assert e.started?
    end
  end

  test "NEW_EVENT_LAGGING/EXCLUDED constants reflect the rank rules" do
    # Pachołek lecił dawniej w fali natychmiastowej; teraz on jest opóźniony
    # i to żółtodziób jest wykluczony zupełnie. Test broni tej decyzji przed
    # przypadkowym swapem z powrotem.
    assert_equal %w[kurzy_pacholek], Event::NEW_EVENT_LAGGING_TITLES
    assert_equal %w[zoltodziob],     Event::NEW_EVENT_EXCLUDED_TITLES
    assert_equal 5.minutes,          Event::NEW_EVENT_LAGGING_DELAY
  end

  test "notify_new_event_subscribers enqueues immediate + delayed waves with the right titles" do
    Event.create!(valid_attrs)

    new_event_jobs = enqueued_jobs.select do |j|
      j["job_class"] == "WebPushNotifier" &&
        ActiveJob::Arguments.deserialize(j["arguments"]).first == :new_event
    end
    immediate = new_event_jobs.find { |j| j["scheduled_at"].blank? }
    delayed   = new_event_jobs.find { |j| j["scheduled_at"].present? }

    immediate_titles = ActiveJob::Arguments.deserialize(immediate["arguments"]).last[:titles]
    delayed_titles   = ActiveJob::Arguments.deserialize(delayed["arguments"]).last[:titles]

    refute_includes immediate_titles, "zoltodziob",     "żółtodziób NIGDY nie dostaje pusha o nowym evencie"
    refute_includes immediate_titles, "kurzy_pacholek", "pachołek leci w fali opóźnionej, nie natychmiastowej"
    %w[kurnikowy_gangster kurnikowy_komendant mistrz_piora].each do |t|
      assert_includes immediate_titles, t, "#{t} dostaje pusha od razu"
    end
    assert_equal %w[kurzy_pacholek], delayed_titles
  end

  test "scope :awaiting_completion returns events past ends_at with no completed_at" do
    Event.delete_all
    ended  = Event.create!(valid_attrs(scheduled_at: 3.hours.ago, ends_at: 1.hour.ago, name: "ended"))
    done   = Event.create!(valid_attrs(scheduled_at: 4.hours.ago, ends_at: 2.hours.ago, completed_at: Time.current, name: "done"))
    future = Event.create!(valid_attrs(scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours, name: "future"))
    assert_includes Event.awaiting_completion, ended
    refute_includes Event.awaiting_completion, done
    refute_includes Event.awaiting_completion, future
  end

  test "creating an upcoming event auto-reserves users of the currently highest rank only" do
    users(:ala).update!(title:      :mistrz_piora)
    users(:bartek).update!(title:   :kurnikowy_gangster)
    users(:cezary).update!(title:   :kurzy_pacholek)
    users(:dominika).update!(title: :zoltodziob)

    event = Event.create!(valid_attrs(capacity: 4))

    reserved_users = event.participations.reserved.includes(:user).map(&:user)
    # Only ala is mistrz_piora; the rest stay unreserved even though capacity is 4.
    assert_equal [ users(:ala) ], reserved_users
  end

  test "creating an event in the past does not trigger reservations" do
    # Bypass the `ends_at_after_scheduled_at` guard? No — validation still applies.
    # Use a future event that we then manually backdate to simulate a never-upcoming one.
    # Simpler: rely on `upcoming_now?` guard — Event with scheduled_at <= now should not seed.
    event = Event.new(valid_attrs(scheduled_at: 5.minutes.ago, ends_at: 1.hour.from_now))
    event.save!(validate: false)
    event.run_callbacks(:commit)  # no-op guard check

    assert_equal 0, event.participations.reserved.count
  end

  test "full? counts reserved + confirmed against capacity" do
    users(:ala).update!(title: :mistrz_piora)
    event = Event.create!(valid_attrs(capacity: 1))
    assert event.full?, "single reserved slot should mark capacity 1 event as full"
  end

  # --- pre_registered_user_ids -----------------------------------------------
  # Virtual attr set from the event-creation form. Confirms non-mistrz users
  # immediately. Mistrz Pióra is filtered out — they always go through the
  # invitation flow (reserved + accept/decline) regardless of pre-registration.

  test "pre_registered_user_ids confirms non-mistrz users immediately" do
    attrs = valid_attrs(capacity: 4, pre_registered_user_ids: [ users(:bartek).id, users(:cezary).id ])
    event = Event.create!(attrs)

    confirmed_users = event.participations.confirmed.includes(:user).order(:position).map(&:user)
    assert_includes confirmed_users, users(:bartek)
    assert_includes confirmed_users, users(:cezary)
  end

  test "pre_registered_user_ids ignores mistrz_piora — they always get an invitation, not auto-confirmation" do
    users(:ala).update!(title: :mistrz_piora)
    attrs = valid_attrs(capacity: 4, pre_registered_user_ids: [ users(:bartek).id, users(:ala).id ])
    event = Event.create!(attrs)

    # Bartek (zwykły user) confirmed od razu.
    confirmed_users = event.participations.confirmed.includes(:user).map(&:user)
    assert_includes confirmed_users, users(:bartek)
    refute_includes confirmed_users, users(:ala)

    # Ala (mistrz_piora) ląduje w reserved przez seed_reservations, NIE w confirmed.
    reserved_users = event.participations.reserved.includes(:user).map(&:user)
    assert_equal [ users(:ala) ], reserved_users
  end

  test "pre_registered_user_ids with only mistrz_piora users — all go through invitation flow" do
    users(:ala).update!(title: :mistrz_piora)
    users(:bartek).update!(title: :mistrz_piora)
    attrs = valid_attrs(capacity: 3, pre_registered_user_ids: [ users(:ala).id, users(:bartek).id ])
    event = Event.create!(attrs)

    # Żaden z mistrzów nie jest confirmed.
    assert_equal 0, event.participations.confirmed.count
    # Obaj dostali rezerwację (zaproszenie).
    reserved_users = event.participations.reserved.includes(:user).map(&:user).to_set
    assert_equal Set[users(:ala), users(:bartek)], reserved_users
  end

  test "pre_registered_user_ids spills onto waitlist when count exceeds capacity" do
    attrs = valid_attrs(
      capacity: 2,
      pre_registered_user_ids: [ users(:ala).id, users(:bartek).id, users(:cezary).id ]
    )
    event = Event.create!(attrs)

    assert_equal 2, event.participations.confirmed.count
    waitlisted = event.participations.waitlist.includes(:user).map(&:user)
    assert_equal [ users(:cezary) ], waitlisted
  end

  test "pre_registered_user_ids skips users blocked by the host" do
    HostBlock.create!(user: users(:bartek), host: hosts(:jan))
    attrs = valid_attrs(capacity: 2, pre_registered_user_ids: [ users(:bartek).id, users(:cezary).id ])
    event = Event.create!(attrs)

    confirmed_users = event.participations.confirmed.includes(:user).map(&:user)
    refute_includes confirmed_users, users(:bartek)
    assert_includes confirmed_users, users(:cezary)
  end

  test "pre_registered_user_ids ignores blank/zero entries (sentinel values)" do
    attrs = valid_attrs(capacity: 4, pre_registered_user_ids: [ "", "0", users(:ala).id.to_s ])
    event = Event.create!(attrs)
    assert_equal [ users(:ala) ], event.participations.confirmed.includes(:user).map(&:user)
  end

  # --- pre_registered_user_ids on UPDATE ------------------------------------
  # Admin scenario: capacity 3 → 6 + checkbox-add 3 new people on the edit form.
  # The new users should occupy the freshly-opened slots as confirmed; existing
  # waitlist stays put (admin's manual pick wins the new slots).

  test "pre_registered_user_ids on update fills new slots after capacity bump" do
    event = Event.create!(valid_attrs(capacity: 3))
    # 3 confirmed already — event is full.
    [ users(:ala), users(:bartek), users(:cezary) ].each_with_index do |u, idx|
      Participation.create!(event: event, user: u, status: :confirmed, position: idx + 1)
    end
    # Plus dwie osoby na waitliście.
    wl_users = 2.times.map { |i| User.create!(first_name: "WL#{i}", last_name: "X", email: "wl#{i}@example.com") }
    wl_users.each_with_index { |u, idx| Participation.create!(event: event, user: u, status: :waitlist, position: idx + 1) }

    new_user = users(:dominika)
    event.update!(capacity: 5, pre_registered_user_ids: [ new_user.id ])

    # Nowy user trafia do confirmed (jest miejsce po bumpie capacity).
    assert_equal "confirmed", event.participations.find_by(user: new_user).status
    # Capacity 5: 3 starych + 1 nowy + 1 promowany z waitlisty = 5.
    assert_equal 5, event.participations.confirmed.count
    # Waitlist skurczył się o 1 (jeden został promowany żeby wypełnić ostatnie miejsce).
    assert_equal 1, event.participations.waitlist.count
  end

  test "pre_registered_user_ids on update with NO capacity change pushes new users to waitlist" do
    event = Event.create!(valid_attrs(capacity: 3))
    [ users(:ala), users(:bartek), users(:cezary) ].each_with_index do |u, idx|
      Participation.create!(event: event, user: u, status: :confirmed, position: idx + 1)
    end

    event.update!(pre_registered_user_ids: [ users(:dominika).id ])

    # Capacity nie wzrosło — nowy user ląduje na waitliście (event był pełny).
    p = event.participations.find_by(user: users(:dominika))
    assert_equal "waitlist", p.status
    assert_equal 3, event.participations.confirmed.count
  end

  test "pre_registered_user_ids on update skips users already participating" do
    event = Event.create!(valid_attrs(capacity: 4))
    Participation.create!(event: event, user: users(:bartek), status: :waitlist, position: 1)

    # Bartek jest już na waitliście. Próba „pre-rejestracji" go ponownie → no-op
    # (a zwłaszcza: nie powinno wybuchnąć na uniqueness).
    assert_nothing_raised do
      event.update!(pre_registered_user_ids: [ users(:bartek).id ])
    end

    bartek_parts = event.participations.where(user: users(:bartek))
    assert_equal 1, bartek_parts.count
    assert_equal "waitlist", bartek_parts.first.status
  end

  test "pre_registered_user_ids on update skips mistrz_piora (invitation flow only)" do
    users(:dominika).update!(title: :mistrz_piora)
    event = Event.create!(valid_attrs(capacity: 4))
    # Mistrz Pióra (Dominika) już dostała rezerwację z seed_reservations.
    initial_reserved = event.participations.reserved.count
    assert_operator initial_reserved, :>=, 1

    # Próba dorzucenia Dominiki przez pre-rejestrację na edit → ignorowane.
    event.update!(pre_registered_user_ids: [ users(:dominika).id ])

    # Nadal tylko jedna partycypacja (rezerwacja), nic confirmed/waitlist nie powstało.
    dominika_parts = event.participations.where(user: users(:dominika))
    assert_equal 1, dominika_parts.count
    assert_equal "reserved", dominika_parts.first.status
  end

  test "pre_registered_user_ids on update assigns confirmed positions after the existing max" do
    event = Event.create!(valid_attrs(capacity: 5))
    Participation.create!(event: event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 2)

    event.update!(pre_registered_user_ids: [ users(:cezary).id ])

    cezary_p = event.participations.find_by(user: users(:cezary))
    assert_equal "confirmed", cezary_p.status
    assert_equal 3, cezary_p.position, "nowa partycypacja powinna iść po istniejących pozycjach, nie kolidować z 1/2"
  end

  # --- capacity bump + pre-registration combo (pełna lista + pełna rezerwa) ---

  test "capacity +1 with pre-registration: new user confirmed AND one waitlister promoted" do
    event = Event.create!(valid_attrs(capacity: 5))

    confirmed = [ users(:ala), users(:bartek), users(:cezary) ]
    confirmed.each_with_index do |u, idx|
      Participation.create!(event: event, user: u, status: :confirmed, position: idx + 1)
    end

    wl_users = 4.times.map { |i| User.create!(first_name: "WL#{i}", last_name: "X", email: "wl#{i}@example.com") }
    wl_users.each_with_index { |u, idx| Participation.create!(event: event, user: u, status: :waitlist, position: idx + 1) }

    # 5 confirmed (3 + prereg + 1 promowany), reszta waitlist
    assert_equal 3, event.participations.confirmed.count
    assert_equal 4, event.participations.waitlist.count

    # Capacity 5→7, plus dopisujemy Dominikę (nie jest na żadnej liście).
    event.update!(capacity: 7, pre_registered_user_ids: [ users(:dominika).id ])

    # Dominika trafiła na confirmed (process_pre_registrations widzi nowe capacity 7,
    # 7 - 3 holding = 4 wolne sloty → confirmed).
    dominika_p = event.participations.find_by(user: users(:dominika))
    assert_equal "confirmed", dominika_p.status

    # Po commicie refill_on_capacity_increase promuje z waitlisty żeby wypełnić
    # do capacity. 7 - 4 confirmed (3 starych + Dominika) = 3 wolne sloty → 3 promowane.
    assert_equal 7, event.participations.confirmed.count
    assert_equal 1, event.participations.waitlist.count
  end

  test "capacity +1 with pre-registration on FULL event: exactly 1 new slot for the pre-registered user" do
    # Event capacity 5, 5 confirmed, 3 na waitliście — full w obu listach.
    event = Event.create!(valid_attrs(capacity: 5))

    confirmed = [ users(:ala), users(:bartek), users(:cezary) ]
    confirmed.each_with_index do |u, idx|
      Participation.create!(event: event, user: u, status: :confirmed, position: idx + 1)
    end
    extra_confirmed = 2.times.map { |i| User.create!(first_name: "C#{i}", last_name: "X", email: "c#{i}@example.com") }
    extra_confirmed.each_with_index { |u, idx| Participation.create!(event: event, user: u, status: :confirmed, position: 4 + idx) }

    wl_users = 3.times.map { |i| User.create!(first_name: "WL#{i}", last_name: "X", email: "wl#{i}@example.com") }
    wl_users.each_with_index { |u, idx| Participation.create!(event: event, user: u, status: :waitlist, position: idx + 1) }

    assert_equal 5, event.participations.confirmed.count
    assert_equal 3, event.participations.waitlist.count

    # Capacity 5→6, dopisujemy Dominikę.
    event.update!(capacity: 6, pre_registered_user_ids: [ users(:dominika).id ])

    # Dominika dostaje jedyne wolne miejsce (pre-registration idzie pierwsza).
    dominika_p = event.participations.find_by(user: users(:dominika))
    assert_equal "confirmed", dominika_p.status

    # refill_on_capacity_increase nie ma już co promować — 6/6.
    assert_equal 6, event.participations.confirmed.count
    # Waitlista bez zmian — jedno nowe miejsce zajęła Dominika, nie waitlister.
    assert_equal 3, event.participations.waitlist.count
  end

  test "capacity +2 with 1 pre-registration on full event: pre-reg fills one slot, waitlister gets the other" do
    event = Event.create!(valid_attrs(capacity: 3))

    [ users(:ala), users(:bartek), users(:cezary) ].each_with_index do |u, idx|
      Participation.create!(event: event, user: u, status: :confirmed, position: idx + 1)
    end

    wl_users = 3.times.map { |i| User.create!(first_name: "WL#{i}", last_name: "X", email: "wl#{i}@example.com") }
    wl_users.each_with_index { |u, idx| Participation.create!(event: event, user: u, status: :waitlist, position: idx + 1) }

    assert_equal 3, event.participations.confirmed.count
    assert_equal 3, event.participations.waitlist.count

    # Capacity 3→5 (+2), dopisujemy Dominikę (+1). Wolne sloty: 2.
    # process_pre_registrations: Dominika → confirmed (jeden z 2 slotów).
    # refill_on_capacity_increase: WL0 promowany → confirmed (drugi slot).
    event.update!(capacity: 5, pre_registered_user_ids: [ users(:dominika).id ])

    dominika_p = event.participations.find_by(user: users(:dominika))
    assert_equal "confirmed", dominika_p.status

    wl0 = event.participations.find_by(user: wl_users[0])
    assert_equal "confirmed", wl0.status

    assert_equal 5, event.participations.confirmed.count
    assert_equal 2, event.participations.waitlist.count
  end

  test "no capacity change with pre-registration on full event: new user goes to waitlist" do
    event = Event.create!(valid_attrs(capacity: 3))

    [ users(:ala), users(:bartek), users(:cezary) ].each_with_index do |u, idx|
      Participation.create!(event: event, user: u, status: :confirmed, position: idx + 1)
    end
    wl = User.create!(first_name: "WL0", last_name: "X", email: "wl0@example.com")
    Participation.create!(event: event, user: wl, status: :waitlist, position: 1)

    # Capacity bez zmian (3), ale dopisujemy Dominikę — musi trafić na waitlistę.
    event.update!(pre_registered_user_ids: [ users(:dominika).id ])

    dominika_p = event.participations.find_by(user: users(:dominika))
    assert_equal "waitlist", dominika_p.status
    assert_equal 2, dominika_p.position

    assert_equal 3, event.participations.confirmed.count
    assert_equal 2, event.participations.waitlist.count
  end

  # --- refill_on_capacity_increase -------------------------------------------
  # When a host bumps capacity mid-event we should pull in waitlisters first
  # and only then look at top-tier reservation candidates.

  test "increasing capacity promotes the oldest waitlister into the new slot" do
    # Capacity 1, ala (mistrz) auto-reserves the only slot. Add bartek to waitlist.
    users(:ala).update!(title: :mistrz_piora)
    event = Event.create!(valid_attrs(capacity: 1))
    Participation.create!(event: event, user: users(:bartek), status: :waitlist, position: 1)

    event.update!(capacity: 2)

    bartek = event.participations.find_by(user: users(:bartek))
    assert_equal "confirmed", bartek.status
  end

  test "decreasing capacity below confirmed headcount demotes the most-recent confirmed to waitlist" do
    event = Event.create!(valid_attrs(capacity: 4))
    a = Participation.create!(event: event, user: users(:ala),      status: :confirmed, position: 1)
    b = Participation.create!(event: event, user: users(:bartek),   status: :confirmed, position: 2)
    c = Participation.create!(event: event, user: users(:cezary),   status: :confirmed, position: 3)
    d = Participation.create!(event: event, user: users(:dominika), status: :confirmed, position: 4)

    event.update!(capacity: 3)

    # Confirmed: 3 osoby (zostają z pozycji 1, 2, 3 — Dominika z pozycji 4 spada).
    assert_equal 3, event.participations.confirmed.count
    [ a, b, c ].each(&:reload)
    [ a, b, c ].each { |p| assert_equal "confirmed", p.status, "#{p.user.first_name} powinien zostać confirmed" }

    # Dominika trafia na FRONT waitlisty (pozycja 1) — jako pierwsza w kolejce
    # do re-promocji gdyby capacity znowu wzrosło.
    d.reload
    assert_equal "waitlist", d.status
    assert_equal 1, d.position
  end

  test "decrease + re-increase round-trip restores the demoted user to confirmed" do
    # Scenariusz użytkownika: 3/3 + 5 waitlist (capacity 3) → bump do 4 → drop do 3.
    event = Event.create!(valid_attrs(capacity: 3))

    # Zakładamy 3 confirmed.
    confirmed_users = [ users(:ala), users(:bartek), users(:cezary) ]
    confirmed_users.each_with_index do |u, idx|
      Participation.create!(event: event, user: u, status: :confirmed, position: idx + 1)
    end

    # Plus 5 waitlist (dorzucamy hostów… nie, twórzmy nowe usery żeby było 5).
    waitlist_users = 5.times.map do |i|
      User.create!(first_name: "WL#{i}", last_name: "X", email: "wl#{i}@example.com")
    end
    waitlist_users.each_with_index do |u, idx|
      Participation.create!(event: event, user: u, status: :waitlist, position: idx + 1)
    end

    # Bump 3 → 4: pierwszy waitlist (WL0) awansuje na confirmed.
    event.update!(capacity: 4)
    wl0 = event.participations.find_by(user: waitlist_users[0])
    assert_equal "confirmed", wl0.status

    # Drop 4 → 3: WL0 (najwyższa pozycja confirmed) wraca na FRONT waitlisty.
    event.update!(capacity: 3)
    wl0.reload
    assert_equal "waitlist", wl0.status
    assert_equal 1, wl0.position

    # Pozostali waitlisterzy zostali przesunięci o 1 — nikt nie wisi w „limbo".
    assert_equal 3, event.participations.confirmed.count
    assert_equal 5, event.participations.waitlist.count
  end

  test "decreasing capacity within the confirmed headcount is a no-op" do
    event = Event.create!(valid_attrs(capacity: 4))
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)

    assert_no_difference -> { event.participations.confirmed.count } do
      event.update!(capacity: 2)
    end
  end

  test "decreasing capacity by more than one demotes multiple confirmed users" do
    event = Event.create!(valid_attrs(capacity: 4))
    Participation.create!(event: event, user: users(:ala),      status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek),   status: :confirmed, position: 2)
    c = Participation.create!(event: event, user: users(:cezary),   status: :confirmed, position: 3)
    d = Participation.create!(event: event, user: users(:dominika), status: :confirmed, position: 4)

    event.update!(capacity: 2)

    assert_equal 2, event.participations.confirmed.count
    # Dwie najnowsze (Cezary pos 3, Dominika pos 4) spadają. Cezary (lower
    # confirmed position) dostaje lepszą pozycję na waitliście (1), Dominika (2).
    c.reload
    d.reload
    assert_equal "waitlist", c.status
    assert_equal "waitlist", d.status
    assert_equal 1, c.position
    assert_equal 2, d.position
  end

  test "updates that don't touch capacity don't trigger any refill" do
    users(:ala).update!(title: :mistrz_piora)
    event = Event.create!(valid_attrs(capacity: 4))
    before = event.participations.holding_slot.count

    event.update!(name: "Inna nazwa")
    assert_equal before, event.participations.holding_slot.count
  end

  # --- log_changes -----------------------------------------------------------
  # Edycje pól z TRACKED_FIELDS muszą zostawiać wpis w `event_changes` żeby
  # historia eventu pokazała kto i kiedy co zmienił. Regresja: gdy
  # refill_on_capacity_increase wołał `event.lock!` PRZED log_changes,
  # `saved_changes` było czyszczone i edycja capacity znikała z logu.

  test "changing capacity creates an EventChange row with previous and new values" do
    event = Event.create!(valid_attrs(capacity: 3))

    assert_difference -> { event.changes_log.where(field: "capacity").count }, +1 do
      event.update!(capacity: 5)
    end

    change = event.changes_log.where(field: "capacity").last
    assert_equal "3", change.previous_value
    assert_equal "5", change.new_value
  end

  test "changing capacity AND scheduled_at logs both fields" do
    event = Event.create!(valid_attrs(capacity: 3))
    new_time = 5.days.from_now.change(usec: 0)

    event.update!(capacity: 5, scheduled_at: new_time, ends_at: new_time + 2.hours)

    fields = event.changes_log.pluck(:field)
    assert_includes fields, "capacity"
    assert_includes fields, "scheduled_at"
    assert_includes fields, "ends_at"
  end

  test "log_changes attributes the edit to edited_by user" do
    event = Event.create!(valid_attrs(capacity: 3))
    event.edited_by = users(:ala)
    event.update!(capacity: 5)

    change = event.changes_log.where(field: "capacity").last
    assert_equal users(:ala), change.user
  end

  # --- notify_users_of_changes ------------------------------------------------

  test "updating a tracked field on an upcoming event enqueues :event_changed push" do
    event = Event.create!(valid_attrs(capacity: 4))
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    clear_enqueued_jobs

    event.update!(scheduled_at: 3.days.from_now, ends_at: 3.days.from_now + 3.hours)

    changed_jobs = enqueued_jobs.select do |j|
      j["job_class"] == "WebPushNotifier" &&
        ActiveJob::Arguments.deserialize(j["arguments"]).first == :event_changed
    end
    assert_equal 1, changed_jobs.size
    args = ActiveJob::Arguments.deserialize(changed_jobs.first["arguments"]).last
    assert_includes args[:changed_fields], "scheduled_at"
    assert_includes args[:changed_fields], "ends_at"
  end

  test "updating a tracked field on a started event does NOT enqueue :event_changed" do
    event = Event.create!(valid_attrs(scheduled_at: 1.hour.ago, ends_at: 2.hours.from_now))
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    clear_enqueued_jobs

    event.update!(capacity: 6)

    changed_jobs = enqueued_jobs.select do |j|
      j["job_class"] == "WebPushNotifier" &&
        ActiveJob::Arguments.deserialize(j["arguments"]).first == :event_changed
    end
    assert_equal 0, changed_jobs.size
  end

  test "updating a non-tracked field does NOT enqueue :event_changed" do
    event = Event.create!(valid_attrs(capacity: 4))
    clear_enqueued_jobs

    event.update!(completed_at: Time.current)

    changed_jobs = enqueued_jobs.select do |j|
      j["job_class"] == "WebPushNotifier" &&
        ActiveJob::Arguments.deserialize(j["arguments"]).first == :event_changed
    end
    assert_equal 0, changed_jobs.size
  end

  # --- name normalization / phantom "changed name" ---------------------------
  # Regresja: API create zapisywało `name: params[:name]` bez strip, więc nazwa
  # z trailing space („2 auta ") przy późniejszej edycji (aplikacja przycina pole
  # → wysyła „2 auta") dawała realną zmianę bajtową renderowaną w historii jako
  # fałszywe „2 auta → 2 auta" (+ push :event_changed).

  test "name is stripped of surrounding whitespace on save" do
    event = Event.create!(valid_attrs(name: "  2 auta  "))
    assert_equal "2 auta", event.name
  end

  test "whitespace-only name change does NOT create an EventChange row" do
    event = Event.create!(valid_attrs(name: "2 auta"))
    # symulacja legacy rekordu ze spacją, z pominięciem normalizacji
    event.update_column(:name, "2 auta ")

    assert_no_difference -> { event.changes_log.where(field: "name").count } do
      event.update!(name: "2 auta")
    end
    assert_equal "2 auta", event.reload.name
  end

  test "whitespace-only name change does NOT enqueue :event_changed push" do
    event = Event.create!(valid_attrs(name: "2 auta"))
    event.update_column(:name, "2 auta ")
    clear_enqueued_jobs

    event.update!(name: "2 auta")

    changed_jobs = enqueued_jobs.select do |j|
      j["job_class"] == "WebPushNotifier" &&
        ActiveJob::Arguments.deserialize(j["arguments"]).first == :event_changed
    end
    assert_equal 0, changed_jobs.size
  end

  test "a real name change still logs an EventChange and enqueues the push" do
    event = Event.create!(valid_attrs(name: "2 auta"))
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    clear_enqueued_jobs

    assert_difference -> { event.changes_log.where(field: "name").count }, +1 do
      event.update!(name: "3 auta")
    end
    change = event.changes_log.where(field: "name").last
    assert_equal "2 auta", change.previous_value
    assert_equal "3 auta", change.new_value

    changed_jobs = enqueued_jobs.select do |j|
      j["job_class"] == "WebPushNotifier" &&
        ActiveJob::Arguments.deserialize(j["arguments"]).first == :event_changed
    end
    assert_equal 1, changed_jobs.size
    args = ActiveJob::Arguments.deserialize(changed_jobs.first["arguments"]).last
    assert_includes args[:changed_fields], "name"
  end

  # ---- Sub-event (cykl) guards ---------------------------------------------

  test "sub-event NIE odpala seed_reservations (rezerwacje idą przez kampanię)" do
    users(:ala).update!(title: :mistrz_piora)
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    campaign.campaign_participations.destroy_all

    sub = Event.create!(valid_attrs(name: "Sub", event_campaign: campaign))
    assert_equal 0, sub.participations.reserved.count,
                 "sub-event nie seeduje rezerwacji — rezerwacje idą przez kampanię"
  end

  test "flat event (bez cyklu) nadal seeduje rezerwacje normalnie" do
    users(:ala).update!(title: :mistrz_piora)
    flat = Event.create!(valid_attrs(name: "Flat"))
    assert_equal 1, flat.participations.reserved.count,
                 "flat event seeduje rezerwacje dla mistrzów"
  end

  test "feed_visible_now? = false dla sub-eventu (blokuje :visit, :append, :remove na :events streamie)" do
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    sub = Event.create!(valid_attrs(name: "Sub", event_campaign: campaign))
    refute sub.send(:feed_visible_now?), "sub-event nie pojawia się w feedzie"
  end

  test "feed_visible_now? = true dla nadchodzącego flat eventu" do
    flat = Event.create!(valid_attrs(name: "Flat"))
    assert flat.send(:feed_visible_now?)
  end

  test "sub-event NIE wysyła globalnego pusha :new_event (cykl wysyła :new_campaign)" do
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    campaign.campaign_participations.destroy_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    Event.create!(valid_attrs(name: "Sub", event_campaign: campaign))
    new_event_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
      j[:job] == WebPushNotifier && j[:args].first == "new_event"
    end
    assert_equal 0, new_event_jobs.size,
                 "sub-event nie wysyła globalnego :new_event"
  end

  test "nowy przyszły sub-event przywraca zakończoną kampanię (completed_at → nil)" do
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    campaign.update!(completed_at: 1.day.ago)

    Event.create!(valid_attrs(name: "Dorzucony termin", event_campaign: campaign))
    assert_nil campaign.reload.completed_at,
               "dorzucenie przyszłego łapania odżywia zakończony rzut"
  end

  test "przeszły sub-event NIE odżywia zakończonej kampanii" do
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    completed_at = 1.day.ago
    campaign.update!(completed_at: completed_at)

    Event.create!(valid_attrs(name: "Backfill", event_campaign: campaign,
                              scheduled_at: 3.days.ago, ends_at: 3.days.ago + 3.hours))
    assert_in_delta completed_at.to_f, campaign.reload.completed_at.to_f, 1,
                    "przeszłe łapanie (backfill) nie rusza completed_at"
  end

  test "sub-event na aktywnej kampanii nie dotyka rekordu kampanii" do
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    original_updated_at = campaign.reload.updated_at

    Event.create!(valid_attrs(name: "Sub", event_campaign: campaign))
    assert_equal original_updated_at, campaign.reload.updated_at,
                 "aktywna kampania nie dostaje zbędnego update!"
  end

  test "sub-event z event_campaign_id flagowany prawidłowo" do
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    sub = Event.create!(valid_attrs(name: "Sub", event_campaign: campaign))
    flat = Event.create!(valid_attrs(name: "Flat"))

    assert_predicate sub, :event_campaign_id?
    refute_predicate flat, :event_campaign_id?
  end
end
