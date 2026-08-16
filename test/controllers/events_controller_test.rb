require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:ala)) }

  test "GET / requires login" do
    delete session_path
    get root_path
    assert_redirected_to login_path
  end

  test "GET / lists upcoming events across all hosts" do
    get root_path
    assert_response :success
    assert_match events(:chickens_tomorrow).name, response.body
    assert_match events(:harvest_next_week).name, response.body
  end

  test "GET / excludes past events" do
    past = Event.create!(host: hosts(:jan), name: "Przeszły", scheduled_at: 2.days.ago,
                          ends_at: 2.days.ago + 2.hours, pay_per_person: 50, capacity: 2)
    get root_path
    assert_no_match past.name, response.body
  end

  test "GET / defaults to 'new' filter and excludes completed events" do
    done = Event.create!(host: hosts(:jan), name: "Zakonczone lapanie",
                         scheduled_at: 3.days.ago, ends_at: 3.days.ago + 2.hours,
                         completed_at: 2.days.ago, pay_per_person: 100, capacity: 3)
    get root_path
    assert_match events(:chickens_tomorrow).name, response.body
    assert_no_match done.name, response.body
  end

  test "GET /?filter=completed lists completed events and hides upcoming" do
    done = Event.create!(host: hosts(:jan), name: "Zakonczone lapanie",
                         scheduled_at: 3.days.ago, ends_at: 3.days.ago + 2.hours,
                         completed_at: 2.days.ago, pay_per_person: 100, capacity: 3)
    get root_path(filter: "completed")
    assert_response :success
    assert_match done.name, response.body
    assert_no_match events(:chickens_tomorrow).name, response.body
  end

  test "GET /?filter=completed includes in-progress events (started, no completed_at)" do
    in_progress = Event.create!(host: hosts(:jan), name: "Wlasnie trwa",
                                scheduled_at: 30.minutes.ago, ends_at: 90.minutes.from_now,
                                pay_per_person: 80, capacity: 3)
    get root_path(filter: "completed")
    assert_response :success
    assert_match in_progress.name, response.body
  end

  test "GET /?filter=bogus falls back to 'new'" do
    get root_path(filter: "bogus")
    assert_response :success
    assert_match events(:chickens_tomorrow).name, response.body
  end

  test "GET /events/:id shows event with host details and map iframe" do
    event = events(:chickens_tomorrow)
    get event_path(event)
    assert_response :success
    assert_match event.name, response.body
    assert_match hosts(:jan).display_name, response.body
    assert_select "iframe[src*='maps.google.com/maps'][src*='output=embed']"
  end

  test "GET /eventy/:id/historia requires login" do
    delete session_path
    get history_event_path(events(:chickens_tomorrow))
    assert_redirected_to login_path
  end

  test "GET /eventy/:id/historia renders event creation + ParticipationEvent audit log" do
    event = events(:chickens_tomorrow)
    # Bartek się zapisuje (joined) i zostaje.
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    # Cezary wchodzi jako waitlist (joined), potem awansowany na confirmed (promoted).
    p = Participation.create!(event: event, user: users(:cezary), status: :waitlist, position: 1)
    p.update!(status: :confirmed, position: 2)

    get history_event_path(event)
    assert_response :success

    assert_match "Utworzono zlecenie",         response.body
    assert_match hosts(:jan).display_name,    response.body
    assert_match users(:bartek).display_name, response.body
    assert_match users(:cezary).display_name, response.body
    # Verby z ParticipationEvent — audit log loguje "joined" (oba) i "promoted" (Cezary).
    assert_match "zapisał się",       response.body
    assert_match "wskoczył z rezerwy", response.body
  end

  test "GET /eventy/:id/historia rozróżnia odrzucenie zaproszenia od anulowania udziału" do
    event = events(:chickens_tomorrow)
    # Bartek dostał zaproszenie (reserved) i je odrzucił (declined).
    invitee = Participation.create!(event: event, user: users(:bartek), status: :reserved,
                                    position: 1, reserved_until: 1.hour.from_now)
    invitee.update!(status: :cancelled)

    # Cezary dołączył dobrowolnie (joined) i sam anulował (cancelled).
    joiner = Participation.create!(event: event, user: users(:cezary), status: :confirmed, position: 1)
    joiner.update!(status: :cancelled)

    get history_event_path(event)
    assert_response :success

    # Bartek w timeline'ie: otrzymał zaproszenie → odrzucił zaproszenie.
    assert_match "otrzymał zaproszenie", response.body
    assert_match "odrzucił zaproszenie", response.body
    # Cezary: zapisał się → anulował udział.
    assert_match "zapisał się",     response.body
    assert_match "anulował udział", response.body
  end

  # ---- Authorization (rank-based gate, see User#can_create_events?) ----
  # Gate: mistrz_piora always passes; kurnikowy_komendant passes only with
  # at least one managed_host. Lower ranks are forbidden.

  test "GET /eventy/nowy as user with no rank is forbidden" do
    sign_in_as(users(:bartek))  # zoltodziob, no managed_hosts
    get new_event_path
    assert_redirected_to root_path
    follow_redirect!
    assert_match "Nie masz uprawnień do planowania zleceń.", response.body
  end

  test "GET /eventy/nowy as mistrz_piora renders form" do
    users(:bartek).update!(title: :mistrz_piora)
    sign_in_as(users(:bartek))
    get new_event_path
    assert_response :success
  end

  test "GET /eventy/nowy as komendant with managed_hosts renders form" do
    users(:bartek).update!(title: :kurnikowy_komendant)
    users(:bartek).managed_hosts << hosts(:jan)
    sign_in_as(users(:bartek))
    get new_event_path
    assert_response :success
  end

  test "GET /eventy/nowy as komendant without managed_hosts is forbidden" do
    users(:bartek).update!(title: :kurnikowy_komendant)
    sign_in_as(users(:bartek))
    get new_event_path
    assert_redirected_to root_path
  end

  test "GET /eventy/nowy as mistrz_piora lists ALL hosts in dropdown" do
    users(:ala).update!(title: :mistrz_piora)
    get new_event_path
    assert_response :success
    assert_match hosts(:jan).display_name,  response.body
    assert_match hosts(:anna).display_name, response.body
    assert_select "input[type='submit']", count: 1
    assert_select "button[type='button'][disabled][aria-disabled='true']", count: 0
  end

  # ---- Authorization: create ----

  test "POST /eventy as non-creator rank is blocked at require_event_creator!" do
    sign_in_as(users(:bartek))
    assert_no_difference "Event.count" do
      post events_path, params: { event: {
        name: "Próba", host_id: hosts(:jan).id,
        event_date: 1.day.from_now.to_date.to_s,
        start_hour: "18", start_minute: "0",
        duration_hours: "2", duration_minutes: "0",
        pay_per_person: 100, capacity: 4
      } }
    end
    assert_redirected_to root_path
  end

  test "POST /eventy as mistrz_piora accepts any host_id" do
    users(:ala).update!(title: :mistrz_piora)
    assert_difference "Event.count", 1 do
      post events_path, params: { event: {
        name: "Mistrz event", host_id: hosts(:anna).id,
        event_date: 1.day.from_now.to_date.to_s,
        start_hour: "18", start_minute: "0",
        duration_hours: "2", duration_minutes: "0",
        pay_per_person: 100, capacity: 4
      } }
    end
    assert_response :redirect
  end

  test "GET / does NOT show 'Zaplanuj zlecenie' button for users without rank" do
    sign_in_as(users(:bartek))
    get root_path
    assert_no_match "Zaplanuj zlecenie", response.body
  end

  test "GET / shows enabled 'Zaplanuj zlecenie' link for mistrz_piora" do
    users(:ala).update!(title: :mistrz_piora)
    get root_path
    assert_match "Zaplanuj zlecenie", response.body
    assert_select "a[href=?]", new_event_path
  end

  test "GET / shows DISABLED 'Zaplanuj zlecenie' for komendant without managed_hosts" do
    users(:bartek).update!(title: :kurnikowy_komendant)
    sign_in_as(users(:bartek))
    get root_path
    assert_response :success
    assert_select "span[aria-disabled='true']", text: /#{Regexp.escape("Zaplanuj zlecenie")}/
    assert_match "Nie masz jeszcze przypisanego gospodarza.", response.body
    assert_select "a[href=?]", new_event_path, count: 0
  end

  test "GET / shows enabled 'Zaplanuj zlecenie' for komendant with managed_hosts" do
    users(:bartek).update!(title: :kurnikowy_komendant)
    users(:bartek).managed_hosts << hosts(:jan)
    sign_in_as(users(:bartek))
    get root_path
    assert_response :success
    assert_match "Zaplanuj zlecenie", response.body
    assert_select "a[href=?]", new_event_path
  end

  test "GET / does NOT show any 'Zaplanuj zlecenie' button for non-admin lower ranks" do
    %i[zoltodziob kurzy_pacholek kurnikowy_gangster].each do |title|
      users(:bartek).update!(title: title)
      sign_in_as(users(:bartek))
      get root_path
      assert_no_match "Zaplanuj zlecenie", response.body, "rank #{title} nie powinien widzieć przycisku"
    end
  end

  # ---- Pre-registration form: hide mistrz_piora ----

  test "GET /eventy/nowy hides mistrz_piora users from 'Zapisz od razu' list" do
    # ala (już mistrz_piora przez admin gate w setupie? sprawdźmy explicite)
    users(:ala).update!(title: :mistrz_piora)
    users(:bartek).update!(title: :kurnikowy_gangster)
    get new_event_path
    assert_response :success

    # Mistrz Pióra (ala) NIE pojawia się w checkboxach pre-rejestracji.
    assert_select "input[type=checkbox][name='event[pre_registered_user_ids][]'][value=?]",
                  users(:ala).id.to_s, count: 0
    # Inni userzy się pojawiają.
    assert_select "input[type=checkbox][name='event[pre_registered_user_ids][]'][value=?]",
                  users(:bartek).id.to_s, count: 1
  end

  # ---- History: capacity edits visible in /historia ----

  test "GET /eventy/:id/historia shows capacity change after admin bumps capacity" do
    event = events(:chickens_tomorrow)
    event.edited_by = users(:ala)
    event.update!(capacity: event.capacity + 2)

    get history_event_path(event)
    assert_response :success
    assert_match "liczbę miejsc", response.body
    assert_match "zmienił", response.body
  end

  # ---- Edit: pre-registration on update ----

  test "GET /eventy/:id/edit hides users already participating from 'Zapisz od razu'" do
    event = events(:chickens_tomorrow)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)

    get edit_event_path(event)
    assert_response :success

    # Bartek już zapisany — nie pojawia się w checkboxach.
    assert_select "input[type=checkbox][name='event[pre_registered_user_ids][]'][value=?]",
                  users(:bartek).id.to_s, count: 0
  end

  test "PATCH /eventy/:id with pre_registered_user_ids adds the user as confirmed (slot dostępny)" do
    event = events(:chickens_tomorrow)
    # Wyczyść auto-rezerwacje z seed_on_create żeby test nie zależał od fixturów.
    event.participations.delete_all

    patch event_path(event), params: { event: {
      name: event.name, host_id: event.host_id,
      event_date: event.scheduled_at.to_date.to_s,
      start_hour: event.scheduled_at.hour, start_minute: event.scheduled_at.min,
      duration_hours: 2, duration_minutes: 0,
      pay_per_person: event.pay_per_person, capacity: 4,
      pre_registered_user_ids: [ users(:bartek).id.to_s ]
    } }
    assert_response :redirect

    assert_equal "confirmed", event.participations.find_by(user: users(:bartek)).status
  end

  test "GET /eventy/:id/kalendarz zwraca .ics z poprawnym SUMMARY/UID/datami" do
    event = events(:chickens_tomorrow)
    get calendar_event_path(event)

    assert_response :success
    assert_match %r{\Atext/calendar}, response.media_type
    assert_match %(filename="event-#{event.id}.ics"), response.headers["Content-Disposition"]

    body = response.body
    assert body.start_with?("BEGIN:VCALENDAR"), "should start with VCALENDAR header"
    assert_match "BEGIN:VEVENT", body
    assert_match "END:VEVENT", body
    assert_match "END:VCALENDAR", body
    assert_match "SUMMARY:#{event.name}", body
    assert_match "UID:event-#{event.id}@", body
    assert_match "DTSTART:#{event.scheduled_at.utc.strftime('%Y%m%dT%H%M%SZ')}", body
    assert_match "DTEND:#{event.ends_at.utc.strftime('%Y%m%dT%H%M%SZ')}", body
    # Lokacja w fixturach ma przecinek („Plac Defilad 1, Warszawa") — w .ics
    # przecinek musi być escaped (`\,`), więc porównujemy do wersji z escape.
    assert_match "LOCATION:#{event.host.location.gsub(',', '\\,').gsub(';', '\\;')}", body
  end

  test "GET /eventy/:id/kalendarz wymaga zalogowania" do
    delete session_path
    get calendar_event_path(events(:chickens_tomorrow))
    assert_redirected_to login_path
  end

  test "GET /eventy/:id/kalendarz escapuje przecinki/średniki w polach tekstowych (RFC 5545)" do
    event = Event.create!(host: hosts(:jan),
                          name: "Kurniki, łapanie; runda I",
                          scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours,
                          pay_per_person: 100, capacity: 2)
    get calendar_event_path(event)

    assert_response :success
    # Nieescaped przecinek/średnik w SUMMARY rozwala parser kalendarza —
    # iCalendar traktuje `,` i `;` jako separatory wartości i parametrów.
    assert_match "SUMMARY:Kurniki\\, łapanie\\; runda I", response.body
  end

  test "GET /eventy/:id/show nie ma już przycisku Dodaj do kalendarza (subskrypcja w profilu)" do
    event = events(:chickens_tomorrow)
    event.participations.delete_all
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)

    get event_path(event)
    assert_response :success
    # Per-event button został usunięty — userzy dodają subskrypcję .ics raz
    # w /profil/edit i wszystkie nadchodzące łapania pojawiają się same.
    assert_no_match "Dodaj do kalendarza", response.body
  end

  test "GET /eventy/:id/show — confirmed pasażer widzi przycisk Zapytaj o podwózkę w karcie kierowcy" do
    event  = events(:chickens_tomorrow)
    driver = users(:ala) # can_drive: true
    rider  = users(:bartek)
    event.participations.delete_all
    Participation.create!(event: event, user: driver, status: :confirmed, position: 1)
    Participation.create!(event: event, user: rider,  status: :confirmed, position: 2)
    offer = CarpoolOffer.create!(event: event, user: driver)

    delete session_path
    sign_in_as(rider)
    get event_path(event)
    assert_response :success

    # Przycisk renderowany dokładnie raz — w karcie kierowcy w sekcji „Podwózki".
    expected_form = %(action="#{event_carpool_requests_path(event)}?carpool_offer_id=#{offer.id}").freeze
    button_form_count = response.body.scan(expected_form).size
    assert_equal 1, button_form_count,
                 "expected exactly one Zapytaj o podwozke button (in the carpool card) — found #{button_form_count}"
    assert_match "Zapytaj o podwózkę", response.body
  end

  test "GET /eventy/:id/show — kierowca nie widzi w swojej karcie przycisku Zapytaj o podwózkę" do
    event  = events(:chickens_tomorrow)
    driver = users(:ala)
    event.participations.delete_all
    Participation.create!(event: event, user: driver, status: :confirmed, position: 1)
    CarpoolOffer.create!(event: event, user: driver)

    get event_path(event) # już zalogowany jako ala (driver) z setup-a
    assert_response :success

    # Driver nie może być pasażerem swojego auta — żadnego "Zapytaj o podwózkę".
    assert_no_match "Zapytaj o podwózkę", response.body
  end

  test "GET /eventy/:id/show — auto pełne pokazuje 'Auto zajęte' zamiast przycisku" do
    event  = events(:chickens_tomorrow)
    driver = users(:ala)
    rider  = users(:bartek)
    event.participations.delete_all
    Participation.create!(event: event, user: driver, status: :confirmed, position: 1)
    Participation.create!(event: event, user: rider,  status: :confirmed, position: 2)
    offer = CarpoolOffer.create!(event: event, user: driver)
    # Wypełniamy 4 fotele
    CarpoolOffer::SEATS.times do |i|
      u = User.create!(first_name: "Pa#{i}", last_name: "Senger#{i}", email: "pa#{i}@example.com")
      Participation.create!(event: event, user: u, status: :confirmed, position: 10 + i)
      CarpoolRequest.create!(carpool_offer: offer, user: u, status: :accepted)
    end

    delete session_path
    sign_in_as(rider)
    get event_path(event)
    assert_response :success

    assert_match "Auto zajęte", response.body
    # W karcie kierowcy nie powinno być przycisku „Zapytaj o podwózkę"
    # (liczymy formularze POST do /podwozki-zapytania na tym evencie).
    expected_form = %(action="#{event_carpool_requests_path(event)}").freeze
    assert_equal 0, response.body.scan(expected_form).size,
                 "auto pełne — nie powinno być żadnego formularza Zapytaj o podwózkę"
  end

  test "GET /eventy/:id/show — czekający pasażer widzi 'Czekasz...' i Wycofaj w karcie kierowcy" do
    event  = events(:chickens_tomorrow)
    driver = users(:ala)
    rider  = users(:bartek)
    event.participations.delete_all
    Participation.create!(event: event, user: driver, status: :confirmed, position: 1)
    Participation.create!(event: event, user: rider,  status: :confirmed, position: 2)
    offer = CarpoolOffer.create!(event: event, user: driver)
    req = CarpoolRequest.create!(carpool_offer: offer, user: rider, status: :pending)

    delete session_path
    sign_in_as(rider)
    get event_path(event)
    assert_response :success

    assert_match "Czekasz na potwierdzenie kierowcy", response.body
    # Wycofaj formularz — DELETE do /podwozki-zapytania/:id
    assert_match %(action="#{event_carpool_request_path(event, req)}"), response.body
  end

  test "GET /eventy/:id/show — confirmed user na waitlist NIE dostaje przycisku Zapytaj o podwózkę" do
    event  = events(:chickens_tomorrow)
    driver = users(:ala)
    waitlisted = users(:cezary)
    event.participations.delete_all
    Participation.create!(event: event, user: driver,     status: :confirmed, position: 1)
    Participation.create!(event: event, user: waitlisted, status: :waitlist,  position: 1)
    CarpoolOffer.create!(event: event, user: driver)

    delete session_path
    sign_in_as(waitlisted)
    get event_path(event)
    assert_response :success

    assert_no_match "Zapytaj o podwózkę", response.body
  end
end
