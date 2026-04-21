require "test_helper"

class ParticipationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:gig-coordinators_tomorrow) # capacity: 4
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

  test "DELETE destroys own confirmed participation (marks cancelled)" do
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    delete event_participation_path(@event)
    p = Participation.find_by(event: @event, user: users(:ala))
    assert p.cancelled?
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
    assert_match I18n.t("events.accept"), response.body
    assert_no_match I18n.t("events.waitlist_accept"), response.body

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
    assert_match I18n.t("events.waitlist_badge"), response.body
    assert_match I18n.t("events.cancel"), response.body
    assert_no_match I18n.t("events.waitlist_accept"), response.body
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
    assert_equal "Potwierdzone - do zobaczenia na łapaniu!", flash[:notice]

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

  test "POST accept on an expired reservation is a no-op (doesn't confirm)" do
    p = Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1,
                              reserved_until: 1.hour.from_now)
    p.update_column(:reserved_until, 5.minutes.ago)
    post accept_event_participation_path(@event)
    assert p.reload.reserved?, "expired reservation must not be acceptable"
  end

  test "POST decline cancels the reservation and invites another top-tier user when one exists" do
    users(:ala).update!(title:    :master)
    users(:bartek).update!(title: :master)        # another top-tier candidate
    users(:cezary).update!(title: :veteran)
    users(:dominika).update!(title: :rookie)

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
    users(:ala).update!(title:    :master)
    users(:bartek).update!(title: :veteran)
    users(:cezary).update!(title: :member)
    users(:dominika).update!(title: :rookie)

    Participation.create!(event: @event, user: users(:ala), status: :reserved, position: 1,
                          reserved_until: 1.hour.from_now)

    post decline_event_participation_path(@event)

    assert Participation.find_by(event: @event, user: users(:ala)).cancelled?
    assert_equal 0, @event.participations.reserved.count,
                 "no other top-tier user → slot stays open, no cascade"
  end

  test "concurrent creates do not exceed capacity" do
    users_list = 6.times.map do |i|
      User.create!(first_name: "Race#{i}", last_name: "Racer#{i}", email: "race#{i}@example.com")
    end

    # Serialize via the same lock the controller uses — test semantic correctness (not race)
    users_list.each do |u|
      sign_in_as(u)
      post event_participation_path(@event)
    end

    assert_equal @event.capacity, @event.participations.confirmed.count
    assert_equal 2, @event.participations.waitlist.count
  end

  test "POST create is rejected when user is blocked for the event's host" do
    HostBlock.create!(user: users(:ala), host: @event.host)
    assert_no_difference "Participation.count" do
      post event_participation_path(@event)
    end
    assert_redirected_to event_path(@event)
    follow_redirect!
    assert_match I18n.t("participations.blocked"), response.body
  end

  test "GET event show renders a blocked banner instead of the accept button" do
    HostBlock.create!(user: users(:ala), host: @event.host)
    get event_path(@event)
    assert_response :success
    assert_match I18n.t("participations.blocked_badge"), response.body
    # Nie ma klikalnego formularza „Akceptuję" – tylko wyłączony przycisk.
    assert_select "form[action=?]", event_participation_path(@event), count: 0
    assert_select "button[disabled][aria-disabled='true']"
  end

  test "blocked user with EXISTING confirmed participation keeps the cancel form" do
    # Edge case: user zapisał się zanim dostał blokadę. Zachowuje własne
    # kontrolki (może anulować), bo banner blokady odpala się tylko przy
    # braku aktywnego participation.
    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    HostBlock.create!(user: users(:ala), host: @event.host)

    get event_path(@event)
    assert_response :success
    assert_match I18n.t("events.confirmed_badge"), response.body
    # Brak bannera blokady — istniejące participation ma pierwszeństwo.
    assert_no_match I18n.t("participations.blocked_badge"), response.body
    # Formularz „Anuluj" (DELETE) jest obecny.
    assert_select "form[action=?][method='post']", event_participation_path(@event) do
      assert_select "input[name='_method'][value='delete']"
    end
  end

  test "participation buttons carry data-haptic attributes for iOS/Android feedback" do
    # „Akceptuję" na pustym evencie → confirm; „Anuluj" dla confirmed → error.
    get event_path(@event)
    assert_select "button[data-haptic='confirm']"

    Participation.create!(event: @event, user: users(:ala), status: :confirmed, position: 1)
    get event_path(@event)
    assert_select "button[data-haptic='error']"
  end

  test "roster shows 'blokada' chip for blocked user in the 'Wszyscy pracownicy' section" do
    HostBlock.create!(user: users(:bartek), host: @event.host)
    get event_path(@event)
    assert_response :success
    # Sekcja „Wszyscy pracownicy" — Bartek ma chip „blokada" zamiast statusu.
    assert_match "blokada", response.body
    assert_select "span", text: /blokada/i
  end
end
