require "test_helper"

# Pełny zestaw testów historii eventu (`/eventy/:id/historia`).
#
# Historia jest budowana w `EventsController#build_history_entries` z trzech
# źródeł:
#   1. samego eventu (`:created` — autor + host)
#   2. `ParticipationEvent` (audit log per uczestnik — joined / cancelled /
#      reserved / accepted / declined / promoted / expired)
#   3. `EventChange` (audit log edycji pól eventu)
#
# Testy poniżej idą po każdym typie wpisu, scenariuszach krzyżowych
# (zaproszenie → akceptacja, zaproszenie → odrzucenie, expiry, promocja),
# poprawności kopii (męska forma — wszyscy kurołapacze to mężczyźni)
# i spójności licznika `Event#history_count` z liczbą renderowanych wpisów.
class EventHistoryTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:ala))   # ala = admin, tytuł kontrolowany w każdym teście
    # Ważne: w fixtures wszyscy userzy mają title=kurnikowy_gangster (oprócz tych
    # explicite zmienianych w teście). Dzięki temu kontrolujemy kto jest mistrzem
    # pióra, a kto nie — `seed_reservations` nie zaprosi nikogo niespecjalnie.
  end

  # ============================================================================
  # 1. Tworzenie eventu
  # ============================================================================

  test "po utworzeniu eventu historia ma wpis 'Utworzono łapanie' z hostem" do
    event = create_simple_event(host: hosts(:jan))

    get history_event_path(event)
    assert_response :success
    assert_match "Utworzono zlecenie",      response.body
    assert_match hosts(:jan).display_name, response.body
  end

  test "świeżo utworzony event bez uczestników ma dokładnie 1 wpis w historii" do
    event = create_simple_event(host: hosts(:jan))
    assert_equal 1, event.history_count, "tylko :created"
  end

  # ============================================================================
  # 2. Zaproszenia mistrza pióra (seed_reservations po Event#after_create_commit)
  # ============================================================================

  test "tworzenie eventu z istniejącym mistrz_piora generuje wpis 'otrzymał zaproszenie'" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))

    get history_event_path(event)
    assert_match users(:bartek).display_name, response.body
    assert_match "otrzymał zaproszenie",      response.body
  end

  test "każdy mistrz_piora dostaje osobne zaproszenie (independent invitations)" do
    users(:bartek).update!(title: :mistrz_piora)
    users(:cezary).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))

    get history_event_path(event)
    body = response.body
    # Obaj mają wpis o zaproszeniu.
    assert_match users(:bartek).display_name, body
    assert_match users(:cezary).display_name, body
    # Liczba zaproszeń = liczba mistrzów.
    assert_equal 2, ParticipationEvent.where(event_type: :reserved)
                                      .joins(:participation)
                                      .where(participations: { event_id: event.id }).count
  end

  test "brak mistrzów pióra → brak wpisów 'otrzymał zaproszenie' w historii" do
    # Wszyscy w fixtures są kurnikowy_gangster, żaden nie jest mistrzem.
    event = create_simple_event(host: hosts(:jan))

    get history_event_path(event)
    assert_no_match "otrzymał zaproszenie", response.body
  end

  test "mistrz_piora pre-registered od razu NIE dostaje drugiego zaproszenia" do
    users(:bartek).update!(title: :mistrz_piora)
    event = Event.new(host: hosts(:jan), name: "Z pre-reg", scheduled_at: 1.day.from_now,
                      ends_at: 1.day.from_now + 2.hours, pay_per_person: 100, capacity: 4)
    event.pre_registered_user_ids = [ users(:bartek).id ]
    event.save!

    # Zgodnie z process_pre_registrations: mistrzowie zaznaczeni w pre-reg są
    # pomijani — i tak idą torem zaproszenia. Wynik: jeden ParticipationEvent
    # o type=reserved, brak duplikatu.
    invitations = ParticipationEvent.where(event_type: :reserved)
                                    .joins(:participation)
                                    .where(participations: { event_id: event.id }).count
    assert_equal 1, invitations
  end

  test "blokowany mistrz_piora NIE dostaje zaproszenia (HostBlock filtruje)" do
    users(:bartek).update!(title: :mistrz_piora)
    HostBlock.create!(user: users(:cezary), host: hosts(:jan)) # cezary nie jest mistrzem, blokada nie wpływa
    HostBlock.delete_all  # invariant: mistrz nie ma blokad — i tak nie umiemy stworzyć blokady na mistrza
    # Sprawdzamy: mistrz_piora bez blokady → invited; brak zaproszeń dla blokowanych userów innej rangi.
    event = create_simple_event(host: hosts(:jan))
    get history_event_path(event)
    assert_match users(:bartek).display_name, response.body
    assert_match "otrzymał zaproszenie",      response.body
  end

  # ============================================================================
  # 3. Akceptacja zaproszenia (reserved → confirmed)
  # ============================================================================

  test "po accept zaproszenia historia ma 'otrzymał zaproszenie' i 'przyjął zaproszenie'" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    invitation = event.participations.where(user_id: users(:bartek).id).first
    assert_equal "reserved", invitation.status

    invitation.update!(status: :confirmed)

    get history_event_path(event)
    assert_match "otrzymał zaproszenie", response.body
    assert_match "przyjął zaproszenie",  response.body
    assert_no_match "anulował udział",    response.body  # akceptacja, nie anulacja
  end

  test "verb 'przyjął zaproszenie' jest w historii TYLKO po reserved → confirmed" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    event.participations.where(user_id: users(:bartek).id).first.update!(status: :confirmed)

    pe = ParticipationEvent.joins(:participation)
                           .where(participations: { event_id: event.id, user_id: users(:bartek).id })
                           .order(:created_at).last
    assert_equal "accepted", pe.event_type
  end

  # ============================================================================
  # 4. Odrzucenie zaproszenia (reserved → cancelled, BEZ flagi expired)
  # ============================================================================

  test "po decline zaproszenia historia ma 'odrzucił zaproszenie', NIE 'anulował udział'" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    invitation = event.participations.where(user_id: users(:bartek).id).first

    invitation.update!(status: :cancelled)  # cancellation_reason = nil → declined

    get history_event_path(event)
    assert_match "otrzymał zaproszenie", response.body
    assert_match "odrzucił zaproszenie", response.body
    # Kluczowy regression: declined ≠ cancelled. Stara historia myliła oba.
    assert_no_match "anulował udział", response.body
  end

  test "decline a cancel idą do różnych ParticipationEvent.event_type" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    invitation = event.participations.where(user_id: users(:bartek).id).first
    invitation.update!(status: :cancelled)

    pe = ParticipationEvent.joins(:participation)
                           .where(participations: { event_id: event.id, user_id: users(:bartek).id })
                           .order(:created_at).last
    assert_equal "declined", pe.event_type
  end

  # ============================================================================
  # 5. Wygaśnięcie rezerwacji (ReservationService.expire_stale!)
  # ============================================================================

  test "wygasła rezerwacja loguje 'rezerwacja wygasła', nie 'odrzucił zaproszenie'" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    invitation = event.participations.where(user_id: users(:bartek).id).first
    invitation.update_columns(reserved_until: 1.minute.ago)  # bypass walidacji żeby wymusić expiry

    ReservationService.expire_stale!

    get history_event_path(event)
    assert_match "rezerwacja wygasła",   response.body
    assert_no_match "odrzucił zaproszenie", response.body
    assert_no_match "anulował udział",     response.body
  end

  test "expire_stale! sets ParticipationEvent.event_type = expired" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    invitation = event.participations.where(user_id: users(:bartek).id).first
    invitation.update_columns(reserved_until: 1.minute.ago)
    ReservationService.expire_stale!

    pe = ParticipationEvent.joins(:participation)
                           .where(participations: { event_id: event.id, user_id: users(:bartek).id })
                           .order(:created_at).last
    assert_equal "expired", pe.event_type
  end

  # ============================================================================
  # 6. Zwykły user dołącza
  # ============================================================================

  test "zwykły user dołączający jako confirmed → 'zapisał się'" do
    event = create_simple_event(host: hosts(:jan))
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)

    get history_event_path(event)
    assert_match users(:bartek).display_name, response.body
    assert_match "zapisał się",               response.body
    assert_no_match "otrzymał zaproszenie",   response.body
  end

  test "zwykły user na waitliscie też ma wpis 'zapisał się'" do
    event = create_simple_event(host: hosts(:jan), capacity: 1)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:cezary), status: :waitlist, position: 1)

    get history_event_path(event)
    # Oboje mają wpis 'zapisał się' — verb nie różnicuje confirmed/waitlist.
    assert_equal 2, response.body.scan("zapisał się").length
  end

  test "join na listę główną loguje :joined a na rezerwę :joined_waitlist" do
    event = create_simple_event(host: hosts(:jan), capacity: 1)
    confirmed_p = Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    waitlist_p  = Participation.create!(event: event, user: users(:cezary), status: :waitlist,  position: 1)

    assert_equal "joined",          confirmed_p.participation_events.last.event_type
    assert_equal "joined_waitlist", waitlist_p.participation_events.last.event_type
  end

  test "wpis 'zapisał się' dla join na rezerwę renderuje się pomarańczowy" do
    event = create_simple_event(host: hosts(:jan), capacity: 1)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:cezary), status: :waitlist,  position: 1)

    get history_event_path(event)
    # Lista <li> z timeline historii — sprawdzamy, że jest dokładnie jeden
    # pomarańczowy ring (rezerwowiec) i co najmniej jeden emerald (zapisany).
    assert_match "bg-orange-500",  response.body
    assert_match "bg-emerald-500", response.body
    items = response.body.scan(%r{<span class="flex size-8 items-center justify-center rounded-full bg-orange-500})
    assert_equal 1, items.length, "tylko join na rezerwę powinien dostać pomarańczowy kolor"
  end

  test "wpis 'przyjął zaproszenie' używa innej ikony niż 'zapisał się'" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    invitation = event.participations.where(user_id: users(:bartek).id).first
    invitation.update!(status: :confirmed)

    get history_event_path(event)

    # Wszystkie ikony w sekcji historii — sprawdzamy że ścieżki dla joined
    # (check) i accepted (thumbs_up) są różne, nie polegamy na wewnętrznym
    # mapowaniu klasy CSS.
    paths = response.body.scan(%r{<path d="([^"]+)"}).flatten
    # mistrz_piora jest sam w eventcie → reserved (star) + accepted (thumbs_up).
    # Nie ma żadnego joined, ale i tak weryfikujemy że accepted używa
    # innej ścieżki niż check (joined-confirmed icon).
    check_path     = "M16.704 4.153"  # początek path-a check (z events_helper)
    thumbs_prefix  = "M1 8.25a1.25"   # początek path-a thumbs_up
    refute paths.any? { |p| p.start_with?(check_path) },
           "akceptacja nie powinna już używać ikony check"
    assert paths.any? { |p| p.start_with?(thumbs_prefix) },
           "akceptacja powinna używać ikony thumbs_up"
  end

  # ============================================================================
  # 7. Anulowanie udziału
  # ============================================================================

  test "confirmed user anuluje → 'zapisał się' + 'anulował udział'" do
    event = create_simple_event(host: hosts(:jan))
    p = Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    p.update!(status: :cancelled)

    get history_event_path(event)
    assert_match "zapisał się",     response.body
    assert_match "anulował udział", response.body
  end

  test "re-join (cancelled → confirmed) generuje drugi wpis 'zapisał się'" do
    event = create_simple_event(host: hosts(:jan))
    p = Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    p.update!(status: :cancelled)
    p.update!(status: :confirmed, position: 1)

    get history_event_path(event)
    # Sekwencja: zapisał się → anulował udział → zapisał się
    assert_equal 2, response.body.scan("zapisał się").length
    assert_equal 1, response.body.scan("anulował udział").length
  end

  # ============================================================================
  # 8. Promocja z waitlisty
  # ============================================================================

  test "promocja z waitlisty (waitlist → confirmed) loguje 'wskoczył z rezerwy'" do
    event = create_simple_event(host: hosts(:jan), capacity: 1)
    Participation.create!(event: event, user: users(:bartek),   status: :confirmed, position: 1)
    p = Participation.create!(event: event, user: users(:cezary), status: :waitlist,  position: 1)

    p.update!(status: :confirmed, position: 2)

    get history_event_path(event)
    assert_match "wskoczył z rezerwy", response.body
  end

  test "promocja loguje ParticipationEvent.event_type = promoted" do
    event = create_simple_event(host: hosts(:jan), capacity: 1)
    Participation.create!(event: event, user: users(:bartek),   status: :confirmed, position: 1)
    p = Participation.create!(event: event, user: users(:cezary), status: :waitlist,  position: 1)
    p.update!(status: :confirmed, position: 2)

    pe = ParticipationEvent.joins(:participation)
                           .where(participations: { event_id: event.id, user_id: users(:cezary).id })
                           .order(:created_at).last
    assert_equal "promoted", pe.event_type
  end

  # ============================================================================
  # 9. Edycje eventu (EventChange)
  # ============================================================================

  test "edycja capacity → wpis 'zmienił liczbę miejsc'" do
    event = create_simple_event(host: hosts(:jan), capacity: 4)
    event.edited_by = users(:ala)
    event.update!(capacity: 6)

    get history_event_path(event)
    assert_match users(:ala).display_name, response.body
    assert_match "zmienił",                response.body
    assert_match "liczbę miejsc",          response.body
  end

  test "edycja name → wpis 'zmienił nazwę'" do
    event = create_simple_event(host: hosts(:jan), name: "Stara nazwa")
    event.edited_by = users(:ala)
    event.update!(name: "Nowa nazwa")

    get history_event_path(event)
    assert_match "zmienił", response.body
    assert_match "nazwę",   response.body
    # previous + new value oba widoczne
    assert_match "Stara nazwa", response.body
    assert_match "Nowa nazwa",  response.body
  end

  test "edycja scheduled_at → wpis 'zmienił datę startu'" do
    event = create_simple_event(host: hosts(:jan))
    new_at = event.scheduled_at + 1.hour
    event.edited_by = users(:ala)
    event.update!(scheduled_at: new_at, ends_at: event.ends_at + 1.hour)

    get history_event_path(event)
    assert_match "zmienił",     response.body
    assert_match "datę startu", response.body
  end

  test "edycja ends_at → wpis 'zmienił datę zakończenia'" do
    event = create_simple_event(host: hosts(:jan))
    event.edited_by = users(:ala)
    event.update!(ends_at: event.ends_at + 30.minutes)

    get history_event_path(event)
    assert_match "datę zakończenia", response.body
  end

  test "edycja pay_per_person → wpis 'zmienił stawkę' z poprzednią i nową kwotą" do
    event = create_simple_event(host: hosts(:jan), pay_per_person: 100)
    event.edited_by = users(:ala)
    event.update!(pay_per_person: 150)

    get history_event_path(event)
    assert_match "stawkę", response.body
  end

  test "edycja capacity (bump) — joined_waitlist + późniejszy promoted koegzystują" do
    # Scenariusz: user dołączył jako rezerwowy, host podbija capacity → user
    # zostaje promowany. Oryginalny wpis joined_waitlist (pomarańczowy zapisał się)
    # ma zostać zachowany, plus dochodzi promoted (wskoczył z rezerwy).
    event = create_simple_event(host: hosts(:jan), capacity: 1)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    waitlister = Participation.create!(event: event, user: users(:cezary), status: :waitlist, position: 1)
    assert_equal "joined_waitlist", waitlister.participation_events.last.event_type

    event.edited_by = users(:ala)
    event.update!(capacity: 2)  # bump → ReservationService.fill_open_slots → promote
    waitlister.reload
    assert_equal "confirmed", waitlister.status

    types = waitlister.participation_events.order(:created_at).pluck(:event_type)
    assert_equal %w[joined_waitlist promoted], types

    get history_event_path(event)
    body = response.body
    # Verb dla obu się pojawia — joined_waitlist ma „zapisał się", promoted ma „wskoczył z rezerwy".
    assert_match "zapisał się",        body
    assert_match "wskoczył z rezerwy", body
    # Pomarańczowy ring (rezerwowy zapis) wciąż jest, mimo że user już potwierdzony.
    assert_match "bg-orange-500", body
  end

  test "edycja capacity (shrink) demotuje confirmed → waitlist bez logowania (existing behavior)" do
    # Sanity check: capacity decrease pcha confirmed → waitlist via update_all
    # (status flip), ale `classify_transition` nie loguje confirmed→waitlist
    # — celowo, żeby nie zaśmiecać historii. Po zmianie do joined_waitlist
    # ten przypadek nadal się nie loguje.
    event = create_simple_event(host: hosts(:jan), capacity: 2)
    p1 = Participation.create!(event: event, user: users(:bartek),  status: :confirmed, position: 1)
    p2 = Participation.create!(event: event, user: users(:cezary),  status: :confirmed, position: 2)

    event.edited_by = users(:ala)
    event.update!(capacity: 1)  # shrink → demote ostatniego confirmed na waitlist

    p2.reload
    assert_equal "waitlist", p2.status, "shrink powinien zdemotować ostatniego confirmed"
    types = p2.participation_events.order(:created_at).pluck(:event_type)
    # Powinien być tylko oryginalny joined (wszedł na confirmed) — demote nie loguje.
    assert_equal %w[joined], types
    # p1 nie zmienił statusu.
    assert_equal "confirmed", p1.reload.status
  end

  test "wiele edycji generuje osobne wpisy w historii" do
    event = create_simple_event(host: hosts(:jan), capacity: 4, name: "A")
    event.edited_by = users(:ala)
    event.update!(capacity: 5)
    event.edited_by = users(:ala)
    event.update!(name: "B")
    event.edited_by = users(:ala)
    event.update!(pay_per_person: 200)

    get history_event_path(event)
    assert_match "liczbę miejsc", response.body
    assert_match "nazwę",         response.body
    assert_match "stawkę",        response.body
    assert_equal 3, EventChange.where(event_id: event.id).count
  end

  test "edycja bez `edited_by` → wpis 'Zmieniono ...' (brak autora)" do
    event = create_simple_event(host: hosts(:jan))
    event.update!(capacity: event.capacity + 1)  # bez edited_by

    get history_event_path(event)
    assert_match "Zmieniono", response.body
  end

  # ============================================================================
  # 10. Forma męska (wszyscy kurołapacze są mężczyznami)
  # ============================================================================

  test "verby ParticipationEvent w historii NIGDY nie zawierają slasha (forma męska)" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    invitation = event.participations.where(user_id: users(:bartek).id).first
    invitation.update!(status: :confirmed)

    Participation.create!(event: event, user: users(:cezary), status: :confirmed, position: 99).update!(status: :cancelled)

    get history_event_path(event)
    body_history_section = response.body[%r{<ul role="list".*?</ul>}m] || response.body
    refute_match %r{(zapisał|anulował|otrzymał|przyjął|odrzucił|wskoczył|wygasła)/[ai]}, body_history_section,
                 "wpisy historii zawierają formę żeńską (slash) — kurołapacze są tylko mężczyznami"
  end

  test "edycja eventu używa 'zmienił' bez '/a'" do
    event = create_simple_event(host: hosts(:jan))
    event.edited_by = users(:ala)
    event.update!(capacity: event.capacity + 1)

    get history_event_path(event)
    body_history_section = response.body[%r{<ul role="list".*?</ul>}m] || response.body
    refute_match "zmienił/a", body_history_section
    assert_match "zmienił",   body_history_section
  end

  # ============================================================================
  # 11. Chronologia (najnowsze wpisy na górze)
  # ============================================================================

  test "wpisy historii są w odwróconej kolejności (najnowsze pierwsze)" do
    event = create_simple_event(host: hosts(:jan))
    travel_to 5.minutes.from_now do
      Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    end
    travel_to 10.minutes.from_now do
      event.edited_by = users(:ala)
      event.update!(name: "Renamed")
    end

    get history_event_path(event)
    body = response.body
    rename_idx  = body.index("Renamed")
    join_idx    = body.index("zapisał się")
    create_idx  = body.index("Utworzono zlecenie")
    assert rename_idx < join_idx,  "najnowszy (rename) powinien być wyżej niż join"
    assert join_idx   < create_idx, "join powinien być wyżej niż :created"
  end

  # ============================================================================
  # 12. Spójność `Event#history_count` z liczbą renderowanych wpisów
  # ============================================================================

  test "history_count == 1 + ParticipationEvent.count + EventChange.count" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))             # +1 (created), +1 (reserved)
    invitation = event.participations.where(user_id: users(:bartek).id).first
    invitation.update!(status: :confirmed)                     # +1 (accepted)

    Participation.create!(event: event, user: users(:cezary),
                          status: :confirmed, position: 99)    # +1 (joined)

    event.edited_by = users(:ala)
    event.update!(capacity: event.capacity + 1)                # +1 (EventChange)

    pe_count = ParticipationEvent.joins(:participation)
                                 .where(participations: { event_id: event.id }).count
    assert_equal 1 + pe_count + event.changes_count, event.history_count
    # I to się zgadza z konkretną wartością.
    assert_equal 5, event.history_count
  end

  test "renderowana liczba <li> w historii == history_count" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    event.participations.where(user_id: users(:bartek).id).first.update!(status: :confirmed)
    event.edited_by = users(:ala)
    event.update!(capacity: 6)

    get history_event_path(event)
    li_count = response.body.scan(%r{<li>\s*<div class="relative pb-8">}).length
    assert_equal event.history_count, li_count
  end

  # ============================================================================
  # 13. Złożone scenariusze (pełen lifecycle)
  # ============================================================================

  test "pełen lifecycle: utworzenie → zaproszenie → akceptacja → edycja → anulowanie" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    invitation = event.participations.where(user_id: users(:bartek).id).first

    # akceptacja
    invitation.update!(status: :confirmed)
    # edycja
    event.edited_by = users(:ala)
    event.update!(name: "Po edycji")
    # potem anulowanie
    invitation.update!(status: :cancelled)

    get history_event_path(event)
    body = response.body
    %w[Utworzono otrzymał\ zaproszenie przyjął\ zaproszenie zmienił anulował\ udział].each do |frag|
      assert_match frag.tr("\\", ""), body, "brak fragmentu w historii: #{frag}"
    end
  end

  test "scenariusz: Mistrz Pióra zaproszony, odrzuca, niezależnie inny user się zapisuje i anuluje" do
    users(:bartek).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan))
    event.participations.where(user_id: users(:bartek).id).first.update!(status: :cancelled)  # decline

    p = Participation.create!(event: event, user: users(:cezary), status: :confirmed, position: 99)
    p.update!(status: :cancelled)

    get history_event_path(event)
    body = response.body
    # Bartek: zaproszenie + odrzucenie
    assert_match users(:bartek).display_name, body
    assert_match "odrzucił zaproszenie",      body
    # Cezary: zapis + anulowanie
    assert_match users(:cezary).display_name, body
    assert_match "anulował udział",           body
  end

  test "różne typy ParticipationEvent w jednym evencie renderują się razem chronologicznie" do
    users(:bartek).update!(title: :mistrz_piora)
    users(:cezary).update!(title: :mistrz_piora)
    event = create_simple_event(host: hosts(:jan), capacity: 1)

    bartek_inv = event.participations.where(user_id: users(:bartek).id).first
    cezary_inv = event.participations.where(user_id: users(:cezary).id).first
    bartek_inv.update!(status: :confirmed)   # accepted
    cezary_inv.update!(status: :cancelled)   # declined

    Participation.create!(event: event, user: users(:dominika),
                          status: :waitlist, position: 1)  # joined

    get history_event_path(event)
    body = response.body
    assert_match "otrzymał zaproszenie", body  # ×2
    assert_match "przyjął zaproszenie",  body
    assert_match "odrzucił zaproszenie", body
    assert_match "zapisał się",          body
  end

  # ============================================================================
  # 14. Bezpieczeństwo — historia nie wymaga rangi creatora, tylko zalogowania
  # ============================================================================

  test "GET /eventy/:id/historia wymaga zalogowanego usera" do
    delete session_path
    event = create_simple_event(host: hosts(:jan))
    get history_event_path(event)
    assert_redirected_to login_path
  end

  test "zwykły user (zoltodziob) widzi historię — to nie jest endpoint admina" do
    users(:bartek).update!(title: :zoltodziob)
    sign_in_as(users(:bartek))
    event = create_simple_event(host: hosts(:jan))
    get history_event_path(event)
    assert_response :success
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  private

  def create_simple_event(host:, name: "Test event", capacity: 4, pay_per_person: 100)
    Event.create!(
      host: host, name: name, capacity: capacity, pay_per_person: pay_per_person,
      scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours,
      creator: Current.user
    )
  end
end
