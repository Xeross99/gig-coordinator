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
    assert_match events(:gig-coordinators_tomorrow).name, response.body
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
    assert_match events(:gig-coordinators_tomorrow).name, response.body
    assert_no_match done.name, response.body
  end

  test "GET /?filter=completed lists completed events and hides upcoming" do
    done = Event.create!(host: hosts(:jan), name: "Zakonczone lapanie",
                         scheduled_at: 3.days.ago, ends_at: 3.days.ago + 2.hours,
                         completed_at: 2.days.ago, pay_per_person: 100, capacity: 3)
    get root_path(filter: "completed")
    assert_response :success
    assert_match done.name, response.body
    assert_no_match events(:gig-coordinators_tomorrow).name, response.body
  end

  test "GET /?filter=bogus falls back to 'new'" do
    get root_path(filter: "bogus")
    assert_response :success
    assert_match events(:gig-coordinators_tomorrow).name, response.body
  end

  test "GET /events/:id shows event with host details and map iframe" do
    event = events(:gig-coordinators_tomorrow)
    get event_path(event)
    assert_response :success
    assert_match event.name, response.body
    assert_match hosts(:jan).display_name, response.body
    assert_select "iframe[src*='maps.google.com/maps'][src*='output=embed']"
  end

  test "GET /eventy/:id/historia requires login" do
    delete session_path
    get history_event_path(events(:gig-coordinators_tomorrow))
    assert_redirected_to login_path
  end

  test "GET /eventy/:id/historia renders event creation + participation entries" do
    event = events(:gig-coordinators_tomorrow)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)
    p = Participation.create!(event: event, user: users(:cezary), status: :waitlist, position: 1)
    # Bump updated_at so the controller emits a separate status_change entry.
    p.update!(status: :confirmed, position: 2, updated_at: 5.seconds.from_now)

    get history_event_path(event)
    assert_response :success

    # Creation entry.
    assert_match "Utworzono wydarzenie",            response.body
    assert_match hosts(:jan).display_name,       response.body
    # Join entries (verbs from participation_action_verb).
    assert_match users(:bartek).display_name,    response.body
    assert_match "dołączył jako potwierdzony",   response.body
    # Status change entry.
    assert_match "został potwierdzony",          response.body
  end

  # ---- Authorization (TEMPORARY admin-only gate, see User#can_create_events?) ----
  # Gate is currently `admin?` regardless of rank. The rank-based gate
  # (master || komendant + managed_hosts) is commented out in user.rb.
  # When the rank gate is restored, these tests must be flipped back.

  test "GET /eventy/nowy as non-admin user is forbidden (admin-only gate)" do
    sign_in_as(users(:bartek))  # not admin
    get new_event_path
    assert_redirected_to root_path
    follow_redirect!
    assert_match I18n.t("events.new_event_forbidden"), response.body
  end

  test "GET /eventy/nowy as non-admin user with master rank is still forbidden" do
    users(:bartek).update!(title: :master)
    sign_in_as(users(:bartek))
    get new_event_path
    assert_redirected_to root_path
  end

  test "GET /eventy/nowy as non-admin komendant with managed_hosts is still forbidden" do
    users(:bartek).update!(title: :captain)
    users(:bartek).managed_hosts << hosts(:jan)
    sign_in_as(users(:bartek))
    get new_event_path
    assert_redirected_to root_path
  end

  test "GET /eventy/nowy as admin renders form and lists ALL hosts in dropdown" do
    get new_event_path
    assert_response :success
    assert_match hosts(:jan).display_name,  response.body
    assert_match hosts(:anna).display_name, response.body
    # Admin always sees the real submit, never the disabled placeholder.
    assert_select "input[type='submit']", count: 1
    assert_select "button[type='button'][disabled][aria-disabled='true']", count: 0
  end

  # ---- Authorization: create ----

  test "POST /eventy as non-admin is blocked at require_event_creator!" do
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

  test "POST /eventy as admin accepts any host_id" do
    assert_difference "Event.count", 1 do
      post events_path, params: { event: {
        name: "Admin event", host_id: hosts(:anna).id,
        event_date: 1.day.from_now.to_date.to_s,
        start_hour: "18", start_minute: "0",
        duration_hours: "2", duration_minutes: "0",
        pay_per_person: 100, capacity: 4
      } }
    end
    assert_response :redirect
  end

  test "GET / does NOT show 'Zaplanuj wydarzenie' button for non-admin without rank" do
    sign_in_as(users(:bartek))
    get root_path
    assert_no_match I18n.t("events.new_event"), response.body
  end

  test "GET / shows enabled 'Zaplanuj wydarzenie' link for admin with event_creator_rank?" do
    # The button area is gated on event_creator_rank? (master || komendant)
    # — admin alone is not enough to render the wrapper.
    users(:ala).update!(title: :master)
    get root_path
    assert_select "a[href=?]", new_event_path, text: /#{Regexp.escape(I18n.t("events.new_event"))}/
  end

  test "GET / shows DISABLED 'Zaplanuj wydarzenie' for non-admin komendant (rank-only, no admin)" do
    users(:bartek).update!(title: :captain)
    sign_in_as(users(:bartek))
    get root_path
    assert_response :success
    # event_creator_rank? gate still renders the wrapper; can_create_events? is false → disabled span.
    assert_select "span[aria-disabled='true']", text: /#{Regexp.escape(I18n.t("events.new_event"))}/
    assert_match I18n.t("events.new_event_disabled_hint"), response.body
    assert_select "a[href=?]", new_event_path, count: 0
  end

  test "GET / shows DISABLED 'Zaplanuj wydarzenie' for non-admin master (admin-only gate)" do
    users(:bartek).update!(title: :master)
    sign_in_as(users(:bartek))
    get root_path
    assert_response :success
    assert_select "span[aria-disabled='true']", text: /#{Regexp.escape(I18n.t("events.new_event"))}/
    assert_select "a[href=?]", new_event_path, count: 0
  end

  test "GET / does NOT show any 'Zaplanuj wydarzenie' button for non-admin lower ranks" do
    %i[rookie member veteran].each do |title|
      users(:bartek).update!(title: title)
      sign_in_as(users(:bartek))
      get root_path
      assert_no_match I18n.t("events.new_event"), response.body, "rank #{title} nie powinien widzieć przycisku"
    end
  end
end
