require "test_helper"

class ParticipationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:chickens_tomorrow) # capacity: 4
    sign_in_as(users(:ala))
  end

  test "POST requires login" do
    delete session_path
    post event_participation_path(@event)
    assert_redirected_to login_path
  end

  test "POST create with spots available creates confirmed participation" do
    assert_difference "Participation.confirmed.count", 1 do
      post event_participation_path(@event)
    end
    p = Participation.order(:id).last
    assert p.confirmed?
    assert_equal 1, p.position
    assert_redirected_to event_path(@event)
  end

  test "POST create when event is full creates waitlist participation" do
    4.times.with_index do |i|
      Participation.create!(event: @event, user: User.create!(first_name: "Filler#{i}", last_name: "Fill#{i}", email: "x#{i}@example.com"),
                            status: :confirmed, position: i + 1)
    end
    assert_difference "Participation.waitlist.count", 1 do
      post event_participation_path(@event)
    end
    p = Participation.order(:id).last
    assert p.waitlist?
    assert_equal 1, p.position
  end

  test "POST create refuses duplicate for same user" do
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    assert_no_difference "Participation.count" do
      post event_participation_path(@event)
    end
    assert_redirected_to event_path(@event)
  end

  test "DELETE destroys own confirmed participation (marks cancelled) when event is full and waitlist exists" do
    @event.update!(capacity: 2)
    Participation.create!(event: @event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:cezary), status: :waitlist,  position: 1)

    delete event_participation_path(@event)

    assert Participation.find_by(event: @event, user: users(:ala)).cancelled?
    assert_redirected_to event_path(@event)
    # Cezary z waitlisty awansuje — lista zostaje pełna.
    assert Participation.find_by(event: @event, user: users(:cezary)).confirmed?
  end

  test "DELETE on confirmed is allowed when event is not full" do
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    delete event_participation_path(@event)
    assert Participation.find_by(event: @event, user: users(:ala)).cancelled?,
           "confirmed cancel must be allowed even when list is not full"
    assert_redirected_to event_path(@event)
  end

  test "DELETE on confirmed is allowed when event is full but waitlist is empty" do
    @event.update!(capacity: 2)
    Participation.create!(event: @event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 2)
    delete event_participation_path(@event)
    assert Participation.find_by(event: @event, user: users(:ala)).cancelled?,
           "confirmed cancel must be allowed even when waitlist is empty"
    assert_redirected_to event_path(@event)
  end

  test "DELETE on waitlist is always allowed (no full+waitlist gate)" do
    @event.update!(capacity: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala),    status: :waitlist,  position: 1)

    delete event_participation_path(@event)

    assert Participation.find_by(event: @event, user: users(:ala)).cancelled?,
           "waitlist cancel must always be allowed"
    assert_redirected_to event_path(@event)
  end

  test "POST create after cancel re-activates the existing participation" do
    Participation.create!(event: @event, user: users(:ala), status: :cancelled, position: 0)
    assert_no_difference "Participation.count" do
      post event_participation_path(@event)
    end
    p = Participation.find_by(event: @event, user: users(:ala))
    assert p.confirmed?, "expected re-join to land as confirmed when capacity available"
  end

  test "cancelling a confirmed spot and re-joining lands at the END of the waitlist when event is full" do
    @event.update!(capacity: 2)

    # Start: ala + bartek confirmed (fill capacity), cezary + dominika on waitlist.
    Participation.create!(event: @event, user: users(:ala),      status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek),   status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:cezary),   status: :waitlist,  position: 1)
    Participation.create!(event: @event, user: users(:dominika), status: :waitlist,  position: 2)

    # Ala cancels → cezary gets promoted to confirmed; dominika still waitlist #2.
    delete event_participation_path(@event)
    assert users(:cezary).participations.find_by(event: @event).confirmed?,
           "expected cezary to be promoted after ala cancels"
    assert users(:dominika).participations.find_by(event: @event).waitlist?,
           "expected dominika to stay on waitlist"

    # Ala re-joins. Event is full (bartek + cezary). She must land at the END of the
    # waitlist (after dominika), not skip ahead of people who were already waiting.
    post event_participation_path(@event)

    ala_p = users(:ala).participations.find_by(event: @event)
    assert ala_p.waitlist?, "expected ala to land on waitlist when event is full"
    assert_operator ala_p.position, :>, users(:dominika).participations.find_by(event: @event).position,
                    "expected ala to land after dominika (end of waitlist)"

    waitlist_order = @event.participations.waitlist.order(:position).map(&:user)
    assert_equal [ users(:dominika), users(:ala) ], waitlist_order,
                 "waitlist order should be [dominika, ala] — earlier waiters keep their spot"
  end

  test "DELETE when not participating does nothing" do
    delete event_participation_path(@event)
    assert_redirected_to event_path(@event)
  end

  test "clicking Akceptuję on a stale page ends up on the waitlist when event filled up in the meantime" do
    @event.update!(capacity: 1)

    # Ala loads the event page — only 0/1 taken, button shows "Akceptuję".
    get event_path(@event)
    assert_response :success
    assert_match Copy::Events::ACCEPT, response.body
    assert_no_match Copy::Events::WAITLIST_ACCEPT, response.body

    # Bartek grabs the last seat before Ala clicks.
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)

    # Ala clicks what was "Akceptuję" — lock re-evaluates capacity, she lands on waitlist.
    assert_difference "@event.participations.waitlist.count", 1 do
      post event_participation_path(@event)
    end
    ala_participation = @event.participations.find_by(user: users(:ala))
    assert ala_participation.waitlist?, "expected Ala to land on waitlist when event filled up"

    # After redirect Ala sees the waitlist badge + cancel button, not the waitlist-accept CTA.
    follow_redirect!
    assert_match Copy::Events::WAITLIST_BADGE, response.body
    assert_match Copy::Events::CANCEL, response.body
    assert_no_match Copy::Events::WAITLIST_ACCEPT, response.body
  end

  test "POST accept flips a live reservation to confirmed" do
    Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1,
                          reserved_until: 1.hour.from_now)
    post accept_event_participation_path(@event)
    p = Participation.find_by(event: @event, user: users(:ala))
    assert p.confirmed?, "expected reserved → confirmed after accept"
    assert_nil p.reserved_until, "reserved_until cleared on acceptance"
    assert_redirected_to event_path(@event)
  end

  test "POST accept sets a confirmation notice that renders as a toast after the redirect" do
    Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1,
                          reserved_until: 1.hour.from_now)
    post accept_event_participation_path(@event)
    assert_equal "Potwierdzone - do zobaczenia na zleceniu!", flash[:notice]

    follow_redirect!
    assert_response :success
    # Toast lives in the shared layout partial. Asserting its text is in the body
    # proves the redirect was followed as a full page load (not trapped inside a
    # turbo-frame, in which case the layout wouldn't re-render).
    assert_match "Potwierdzone", response.body
  end

  test "POST decline sets a notice that renders as a toast after the redirect" do
    Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1,
                          reserved_until: 1.hour.from_now)
    post decline_event_participation_path(@event)
    assert_match(/Odrzucone/, flash[:notice])

    follow_redirect!
    assert_response :success
    assert_match "Odrzucone", response.body
  end

  test "reservation accept/decline buttons target _top so submission breaks out of the turbo-frame" do
    # Reproduces the bug "confirmation toast only appears on refresh": without
    # data-turbo-frame=_top the button_to form stays inside the participation
    # turbo-frame, the redirect is extracted frame-scoped, and the layout (with
    # the flash toast) never re-renders.
    Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1,
                          reserved_until: 1.hour.from_now)
    get event_path(@event)
    assert_response :success

    assert_select "form[action=?][data-turbo-frame=?]", accept_event_participation_path(@event), "_top"
    assert_select "form[action=?][data-turbo-frame=?]", decline_event_participation_path(@event), "_top"
  end

  test "POST accept falls back to waitlist when capacity is already filled by other mistrzowie" do
    # Symulujemy „za dużo zaproszeń, za mało miejsc": event capacity 1,
    # 2 inne osoby już są confirmed, ala ma rezerwację. Ala klika Akceptuję —
    # confirmed jest pełne, więc spada na waitlistę.
    @event.participations.delete_all
    @event.update!(capacity: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:ala),    status: :reserved,  position: 1,
                          reserved_until: 1.hour.from_now)

    post accept_event_participation_path(@event)
    p = Participation.find_by(event: @event, user: users(:ala))
    assert p.waitlist?, "capacity full → reserved spada na waitlistę zamiast pchać confirmed ponad limit"
    assert_nil p.reserved_until
    assert_match "Lista jest pełna", flash[:notice]
  end

  test "POST accept on an expired reservation is a no-op (doesn't confirm)" do
    p = Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1,
                              reserved_until: 1.hour.from_now)
    p.update_column(:reserved_until, 5.minutes.ago)
    post accept_event_participation_path(@event)
    assert p.reload.reserved?, "expired reservation must not be acceptable"
  end

  test "POST decline cancels the reservation and invites another top-tier user when one exists" do
    users(:ala).update!(title:    :mistrz_piora)
    users(:bartek).update!(title: :mistrz_piora)        # another top-tier candidate
    users(:cezary).update!(title: :kurnikowy_gangster)
    users(:dominika).update!(title: :zoltodziob)

    Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1,
                          reserved_until: 1.hour.from_now)

    post decline_event_participation_path(@event)

    ala_p = Participation.find_by(event: @event, user: users(:ala))
    assert ala_p.cancelled?, "expected ala to be cancelled after decline"

    invited = @event.participations.reserved.first
    assert invited, "expected a new reservation for bartek (same top tier)"
    assert_equal users(:bartek), invited.user
    refute @event.participations.find_by(user: users(:cezary))&.reserved?,
           "cezary is lower tier and must not be invited"
  end

  test "POST decline leaves the slot empty when no other top-tier user exists" do
    users(:ala).update!(title:    :mistrz_piora)
    users(:bartek).update!(title: :kurnikowy_gangster)
    users(:cezary).update!(title: :kurzy_pacholek)
    users(:dominika).update!(title: :zoltodziob)

    Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1,
                          reserved_until: 1.hour.from_now)

    post decline_event_participation_path(@event)

    assert Participation.find_by(event: @event, user: users(:ala)).cancelled?
    assert_equal 0, @event.participations.reserved.count,
                 "no other top-tier user → slot stays open, no cascade"
  end

  test "concurrent creates do not exceed capacity" do
    users_list = 6.times.map do |i|
      User.create!(first_name: "Race#{i}", last_name: "Racer#{i}", email: "race#{i}@example.com",
                   title: :kurnikowy_gangster)
    end

    # Serialize via the same lock the controller uses — test semantic correctness (not race)
    users_list.each do |u|
      sign_in_as(u)
      post event_participation_path(@event)
    end

    assert_equal @event.capacity, @event.participations.confirmed.count
    assert_equal 2, @event.participations.waitlist.count
  end

  test "POST create succeeds for kurzy_pacholek (sanity check that block isn't over-broad)" do
    users(:ala).update!(title: :kurzy_pacholek)
    assert_difference "Participation.confirmed.count", 1 do
      post event_participation_path(@event)
    end
  end

  test "DELETE destroy still works for a zoltodziob who has an existing participation" do
    # Defensywnie: jeśli admin zdegradował kogoś po fakcie zapisu, user dalej
    # musi móc anulować swoje istniejące uczestnictwo. Block dotyczy tylko
    # tworzenia nowych zgłoszeń (POST create / accept).
    @event.update!(capacity: 2)
    Participation.create!(event: @event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:cezary), status: :waitlist,  position: 1)
    users(:ala).update!(title: :zoltodziob)

    delete event_participation_path(@event)
    assert users(:ala).participations.find_by(event: @event).cancelled?,
      "zoltodziob z istniejącym uczestnictwem dalej musi móc anulować"
  end

  test "POST create is rejected for zoltodziob (view-only role)" do
    users(:ala).update!(title: :zoltodziob)
    assert_no_difference "Participation.count" do
      post event_participation_path(@event)
    end
    assert_redirected_to event_path(@event)
    follow_redirect!
    assert_match Copy::Participations::ZOLTODZIOB_VIEW_ONLY, response.body
  end

  test "POST accept is rejected for zoltodziob (defense in depth — they have no reservations anyway)" do
    users(:ala).update!(title: :zoltodziob)
    # Sztucznie wbijamy rezerwację (normalnie zoltodziob jej nie dostanie),
    # żeby pokazać że akcja accept i tak by go odrzuciła nawet z deeplinka.
    Participation.create!(event: @event, user: users(:ala), status: :reserved,
                           position: 1, reserved_until: 30.minutes.from_now)

    post accept_event_participation_path(@event)
    assert_redirected_to event_path(@event)
    follow_redirect!
    assert_match Copy::Participations::ZOLTODZIOB_VIEW_ONLY, response.body
    refute users(:ala).participations.find_by(event: @event).confirmed?,
      "zoltodziob nie powinien móc zaakceptować rezerwacji"
  end

  test "GET event show renders a view-only banner for zoltodziob instead of the accept button" do
    users(:ala).update!(title: :zoltodziob)
    get event_path(@event)
    assert_response :success
    assert_match Copy::Participations::ZOLTODZIOB_BADGE, response.body
    assert_select "form[action=?]", event_participation_path(@event), count: 0
    assert_select "button[disabled][aria-disabled='true']"
  end

  test "POST create is rejected when user is blocked for the event's host" do
    HostBlock.create!(user: users(:ala), host: @event.host)
    assert_no_difference "Participation.count" do
      post event_participation_path(@event)
    end
    assert_redirected_to event_path(@event)
    follow_redirect!
    assert_match Copy::Participations::BLOCKED, response.body
  end

  test "GET event show renders a blocked banner instead of the accept button" do
    HostBlock.create!(user: users(:ala), host: @event.host)
    get event_path(@event)
    assert_response :success
    assert_match Copy::Participations::BLOCKED_BADGE, response.body
    # Nie ma klikalnego formularza „Akceptuję" – tylko wyłączony przycisk.
    assert_select "form[action=?]", event_participation_path(@event), count: 0
    assert_select "button[disabled][aria-disabled='true']"
  end

  test "blocked user with EXISTING confirmed participation keeps the cancel form" do
    # Edge case: user zapisał się zanim dostał blokadę. Zachowuje własne
    # kontrolki (może anulować), bo banner blokady odpala się tylko przy
    # braku aktywnego participation. Dodatkowo musi być spełniony nowy
    # warunek (lista pełna + ktoś w rezerwie), inaczej przycisk się
    # wyszarza — testujemy że formularz jest aktywny.
    @event.update!(capacity: 2)
    Participation.create!(event: @event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:cezary), status: :waitlist,  position: 1)
    HostBlock.create!(user: users(:ala), host: @event.host)

    get event_path(@event)
    assert_response :success
    assert_match Copy::Events::CONFIRMED_BADGE, response.body
    # Brak bannera blokady — istniejące participation ma pierwszeństwo.
    assert_no_match Copy::Participations::BLOCKED_BADGE, response.body
    # Formularz „Anuluj" (DELETE) jest obecny.
    assert_select "form[action=?][method='post']", event_participation_path(@event) do
      assert_select "input[name='_method'][value='delete']"
    end
  end

  test "participation buttons carry data-haptic attributes for iOS/Android feedback" do
    # „Akceptuję" na pustym evencie → confirm; „Anuluj" dla confirmed → error.
    # Cancel-haptic pojawia się tylko gdy faktycznie można anulować
    # (lista pełna + ktoś w rezerwie), więc dopełniamy event.
    get event_path(@event)
    assert_select "button[data-haptic='confirm']"

    @event.update!(capacity: 2)
    Participation.create!(event: @event, user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: @event, user: users(:bartek), status: :confirmed, position: 2)
    Participation.create!(event: @event, user: users(:cezary), status: :waitlist,  position: 1)
    get event_path(@event)
    assert_select "button[data-haptic='error']"
  end


  test "POST create on an expired reserved participation re-activates it as confirmed" do
    # Sweeper jeszcze nie przebiegł, user widzi generyczny „Akceptuję" (bo
    # reservation_expired? = true) — kliknięcie musi zadziałać, nie wisieć.
    p = Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1, reserved_until: 5.minutes.ago)
    assert p.reservation_expired?

    post event_participation_path(@event)
    p.reload
    assert p.confirmed?
    assert_nil p.reserved_until
    assert_redirected_to event_path(@event)
  end

  # --- event lock (started?) ---------------------------------------------------
  # Wszystkie 4 mutujące akcje (create / destroy / accept / decline) są zamykane
  # przez `enforce_event_lock!` z momentem scheduled_at.

  test "POST create blocked once event has started" do
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    assert_no_difference "Participation.count" do
      post event_participation_path(@event)
    end
    assert_redirected_to event_path(@event)
    assert_equal "Zlecenie już się rozpoczęło - zmiany niemożliwe.", flash[:alert]
  end

  test "DELETE destroy blocked once event has started" do
    p = Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    delete event_participation_path(@event)
    assert p.reload.confirmed?, "participation should not be cancelled when event is locked"
    assert_equal "Zlecenie już się rozpoczęło - zmiany niemożliwe.", flash[:alert]
  end

  test "POST accept blocked once event has started" do
    p = Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1, reserved_until: 1.hour.from_now)
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    post accept_event_participation_path(@event)
    assert p.reload.reserved?
    assert_equal "Zlecenie już się rozpoczęło - zmiany niemożliwe.", flash[:alert]
  end

  test "POST decline blocked once event has started" do
    p = Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1, reserved_until: 1.hour.from_now)
    @event.update_columns(scheduled_at: 1.minute.ago, ends_at: 1.hour.from_now)
    post decline_event_participation_path(@event)
    assert p.reload.reserved?
    assert_equal "Zlecenie już się rozpoczęło - zmiany niemożliwe.", flash[:alert]
  end

  # ---- Sub-event (cykl łapań) -----------------------------------------------

  test "POST create na sub-evencie kampanii działa bezpośrednio" do
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    campaign.campaign_participations.destroy_all
    sub = Event.create!(
      host: hosts(:jan), event_campaign: campaign, name: "Sub",
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 4
    )
    sub.participations.destroy_all

    assert_difference -> { sub.participations.count }, +1 do
      post event_participation_path(sub)
    end
    assert_equal "confirmed", sub.participations.find_by(user: users(:ala)).status
  end

  test "DELETE destroy na sub-evencie WYPISUJE z konkretnego terminu (bez wpływu na kampanię)" do
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    campaign.campaign_participations.destroy_all
    cp = CampaignParticipation.create!(event_campaign: campaign, user: users(:ala),
                                       status: :confirmed, position: 1)
    sub = Event.create!(
      host: hosts(:jan), event_campaign: campaign, name: "Sub",
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours,
      pay_per_person: 100, capacity: 4
    )
    sub.participations.destroy_all
    Participation.create!(event: sub, user: users(:ala), status: :confirmed, position: 1)

    delete event_participation_path(sub)

    sub_p = sub.participations.find_by(user: users(:ala))
    assert_equal "cancelled", sub_p.reload.status, "sub-event participation cancelled"
    cp.reload
    assert_equal "confirmed", cp.status, "campaign membership untouched"
    assert_redirected_to event_path(sub)
  end

  # --- Ponowne dołączenie do łapania po wypisaniu się -------------------------
  # Bug: po „Wypisz mnie z tego łapania" gałąź sub-eventowa participation
  # buttona nie renderowała ŻADNEGO przycisku (active.find_by → nil → tylko
  # amber box „Zapis przez rzut"), więc członek rzutu nie mógł wrócić na
  # łapanie, z którego się wypisał. Backend (#create) reaktywację umie —
  # brakowało formularza w widoku.

  test "GET show sub-eventu po wypisaniu pokazuje przycisk ponownego dołączenia" do
    campaign, sub = create_campaign_with_sub
    Participation.create!(event: sub, user: users(:ala), status: :confirmed, position: 1)

    delete event_participation_path(sub)
    assert_equal "cancelled", sub.participations.find_by(user: users(:ala)).status

    get event_path(sub)
    assert_response :success
    assert sub_event_join_forms(sub).any?,
      "po wypisaniu z łapania powinien być formularz ponownego dołączenia (POST na uczestnictwo, bez _method=delete)"
  end

  test "GET show sub-eventu po wypisaniu pokazuje przycisk dołączenia także gdy łapanie jest pełne" do
    # Pełny sub-event → powrót prowadzi na listę rezerwową, ale przycisk musi być.
    campaign, sub = create_campaign_with_sub(sub_capacity: 1)
    Participation.create!(event: sub, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: sub, user: users(:ala), status: :cancelled, position: 0)

    get event_path(sub)
    assert_response :success
    assert sub_event_join_forms(sub).any?,
      "wypisany członek rzutu powinien móc wrócić na pełne łapanie (na listę rezerwową)"
  end

  test "GET show sub-eventu dla confirmed pokazuje tylko wypisanie, bez formularza dołączenia" do
    # Kontrola negatywna: przycisk powrotu nie może być renderowany zawsze.
    campaign, sub = create_campaign_with_sub
    Participation.create!(event: sub, user: users(:ala), status: :confirmed, position: 1)

    get event_path(sub)
    assert_response :success
    assert_equal 0, sub_event_join_forms(sub).count,
      "confirmed nie powinien widzieć formularza dołączenia"
    assert_select "form[action=?][method='post']", event_participation_path(sub) do
      assert_select "input[name='_method'][value='delete']"
    end
  end

  test "POST create na sub-evencie reaktywuje wypisane uczestnictwo jako confirmed" do
    campaign, sub = create_campaign_with_sub
    Participation.create!(event: sub, user: users(:ala), status: :cancelled, position: 0)

    assert_no_difference "Participation.count" do
      post event_participation_path(sub)
    end

    assert_equal "confirmed", sub.participations.find_by(user: users(:ala)).status
    assert_equal "confirmed", campaign.campaign_participations.find_by(user: users(:ala)).status,
      "reaktywacja na sub-evencie nie dotyka primary rostera"
    assert_redirected_to event_path(sub)
  end

  test "POST create na pełnym sub-evencie reaktywuje wypisane uczestnictwo na waitlistę" do
    _campaign, sub = create_campaign_with_sub(sub_capacity: 1)
    Participation.create!(event: sub, user: users(:bartek), status: :confirmed, position: 1)
    Participation.create!(event: sub, user: users(:ala), status: :cancelled, position: 0)

    assert_no_difference "Participation.count" do
      post event_participation_path(sub)
    end

    p = sub.participations.find_by(user: users(:ala))
    assert_equal "waitlist", p.status
    assert_equal 1, p.position
    assert_equal "confirmed", sub.participations.find_by(user: users(:bartek)).status
  end

  private

  # Kampania z zalogowaną alą confirmed na primary rosterze + jeden przyszły
  # sub-event. Auto-seedy (rezerwacje mistrzów, CampaignSubEventSeeder) są
  # wycinane, żeby stan rosteru był w pełni deterministyczny — jak w
  # pozostałych testach sub-eventowych powyżej.
  def create_campaign_with_sub(sub_capacity: 4)
    campaign = EventCampaign.create!(host: hosts(:jan), name: "Cykl", capacity: 4)
    campaign.campaign_participations.destroy_all
    CampaignParticipation.create!(event_campaign: campaign, user: users(:ala),
                                  status: :confirmed, position: 1)
    sub = Event.create!(
      host: hosts(:jan), event_campaign: campaign, name: "Sub",
      scheduled_at: 2.days.from_now, ends_at: 2.days.from_now + 2.hours,
      pay_per_person: 100, capacity: sub_capacity
    )
    sub.participations.destroy_all
    [ campaign, sub ]
  end

  # Formularze dołączenia (POST bez _method=delete) celujące w uczestnictwo
  # danego eventu — odsiewa formularz „Wypisz mnie" (button_to DELETE też
  # renderuje method='post', różni się hidden inputem _method).
  def sub_event_join_forms(event)
    css_select("form[action='#{event_participation_path(event)}'][method='post']")
      .reject { |form| form.css("input[name='_method']").any? }
  end
end
