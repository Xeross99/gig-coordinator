require "test_helper"

module HostAdmin
  class EventsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as(hosts(:jan))
    end

    test "redirects to login when not signed in as host" do
      delete session_path
      get host_events_path
      assert_redirected_to login_path
    end

    test "redirects to login when signed in as user (not host)" do
      delete session_path
      sign_in_as(users(:ala))
      get host_events_path
      assert_redirected_to login_path
    end

    test "GET index lists only own events" do
      get host_events_path
      assert_response :success
      assert_match "Lapanie kur", response.body
      assert_no_match "Zbieranie truskawek", response.body
    end

    test "GET new renders form" do
      get new_host_event_path
      assert_response :success
      assert_select "form[action=?]", host_events_path
    end

    test "POST create valid creates event and redirects to show" do
      date = 1.day.from_now.to_date
      assert_difference "Event.count", 1 do
        post host_events_path, params: { event: {
          name: "Nowy event",
          event_date: date.to_s,
          start_hour:   8,
          start_minute: 0,
          duration_hours:   3,
          duration_minutes: 30,
          pay_per_person: 100,
          capacity: 5
        } }
      end
      new_event = Event.order(:id).last
      assert_equal hosts(:jan), new_event.host
      assert_equal date, new_event.scheduled_at.to_date
      assert_equal date, new_event.ends_at.to_date
      assert_equal 3.5 * 3600, (new_event.ends_at - new_event.scheduled_at).to_i
      assert_redirected_to host_event_path(new_event)
    end

    test "POST create invalid re-renders new with 422" do
      assert_no_difference "Event.count" do
        post host_events_path, params: { event: { name: "" } }
      end
      assert_response :unprocessable_content
    end

    test "GET show renders event" do
      get host_event_path(events(:gig-coordinators_tomorrow))
      assert_response :success
      assert_match "Lapanie kur", response.body
    end

    test "cannot show other hosts event" do
      get host_event_path(events(:harvest_next_week))
      assert_response :not_found
    end

    test "PATCH update with valid attributes updates and redirects" do
      event = events(:gig-coordinators_tomorrow)
      patch host_event_path(event), params: { event: { name: "Nowa nazwa" } }
      assert_equal "Nowa nazwa", event.reload.name
      assert_redirected_to host_event_path(event)
    end

    test "DELETE destroys own event" do
      event = events(:gig-coordinators_tomorrow)
      assert_difference "Event.count", -1 do
        delete host_event_path(event)
      end
      assert_redirected_to host_events_path
    end

    # ---- Historia zapisów (Host panel „Historia zapisów" section) ----

    # Skrawek HTML od nagłówka „Historia zapisów" w dół — odfiltrowuje sekcję
    # rosteru powyżej, żeby asercje kolejności nie łapały nazw z innej sekcji.
    def history_section(body)
      idx = body.index("Historia zapisów")
      assert idx, "nie znaleziono sekcji Historia zapisów"
      body[idx..]
    end

    test "GET show renders empty-state for event with no participations" do
      event = events(:gig-coordinators_tomorrow)
      get host_event_path(event)
      assert_response :success

      assert_match "Historia zapisów", response.body
      assert_match "Nic się jeszcze nie zadziało.", response.body
      assert_match "Historia zapisów (0)", response.body
    end

    test "GET show renders Polish labels for each event_type" do
      event = events(:gig-coordinators_tomorrow)
      # Zbudujmy ręcznie po jednym wpisie każdego typu, podpinając pod
      # participation istniejącego usera — wystarczy jeden, bo testujemy
      # tylko render etykiet.
      p = Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)
      # p ma już :joined z after_commit; dołóż resztę enum-wartości.
      %i[cancelled reserved accepted declined promoted expired].each do |t|
        p.participation_events.create!(event_type: t)
      end

      get host_event_path(event)
      assert_response :success

      html = history_section(response.body)
      assert_match "zapisał się",              html
      assert_match "zrezygnował",              html
      assert_match "dostał rezerwację",        html
      assert_match "potwierdził rezerwację",   html
      assert_match "odrzucił rezerwację",      html
      assert_match "awansował z listy rezerwowej", html
      assert_match "rezerwacja wygasła",       html
    end

    test "GET show lists history newest-first (desc order)" do
      event = events(:gig-coordinators_tomorrow)
      p_ala     = travel_to(5.minutes.ago) { Participation.create!(event: event, user: users(:ala),    status: :confirmed, position: 1) }
      p_bartek  = travel_to(3.minutes.ago) { Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 2) }
      p_cezary  = travel_to(1.minute.ago)  { Participation.create!(event: event, user: users(:cezary), status: :confirmed, position: 3) }

      get host_event_path(event)
      assert_response :success

      html = history_section(response.body)
      cezary_idx = html.index(users(:cezary).display_name)
      bartek_idx = html.index(users(:bartek).display_name)
      ala_idx    = html.index(users(:ala).display_name)

      assert cezary_idx && bartek_idx && ala_idx,
             "wszyscy trzej userzy muszą pojawić się w sekcji historii"
      assert cezary_idx < bartek_idx, "najnowszy wpis (Cezary) powinien być wyżej niż starszy (Bartek)"
      assert bartek_idx < ala_idx,    "Bartek powinien być wyżej niż najstarszy (Ala)"
    end

    test "GET show scopes history to current event only (nie pokazuje wpisów z innych eventów)" do
      event       = events(:gig-coordinators_tomorrow)
      other_event = events(:harvest_next_week)
      # Ala zapisuje się na „nasz" event...
      Participation.create!(event: event,       user: users(:ala),    status: :confirmed, position: 1)
      # ...a Bartek na event Anny — historia nie powinna się przesiąknąć.
      Participation.create!(event: other_event, user: users(:bartek), status: :confirmed, position: 1)

      get host_event_path(event)
      assert_response :success

      html = history_section(response.body)
      assert_match users(:ala).display_name,    html
      refute_match users(:bartek).display_name, html,
                   "historia powinna być zeskopowana do tego eventu — Bartek zapisał się gdzie indziej"
      assert_match "Historia zapisów (1)", response.body
    end

    test "GET show history count matches number of entries" do
      event = events(:gig-coordinators_tomorrow)
      p = Participation.create!(event: event, user: users(:ala), status: :reserved, position: 1,
                                reserved_until: 1.hour.from_now)
      p.update!(status: :confirmed, reserved_until: nil)
      p.update!(status: :cancelled)
      # 3 wpisy: :reserved, :accepted, :cancelled

      get host_event_path(event)
      assert_response :success
      assert_match "Historia zapisów (3)", response.body
    end
  end
end
