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

  # ---- Authorization (rank-based gate, see User#can_create_events?) ----
  # Gate: master always passes; captain passes only with
  # at least one managed_host. Lower ranks are forbidden.

  test "GET /eventy/nowy as user with no rank is forbidden" do
    sign_in_as(users(:bartek))  # rookie, no managed_hosts
    get new_event_path
    assert_redirected_to root_path
    follow_redirect!
    assert_match I18n.t("events.new_event_forbidden"), response.body
  end

  test "GET /eventy/nowy as master renders form" do
    users(:bartek).update!(title: :master)
    sign_in_as(users(:bartek))
    get new_event_path
    assert_response :success
  end

  test "GET /eventy/nowy as komendant with managed_hosts renders form" do
    users(:bartek).update!(title: :captain)
    users(:bartek).managed_hosts << hosts(:jan)
    sign_in_as(users(:bartek))
    get new_event_path
    assert_response :success
  end

  test "GET /eventy/nowy as komendant without managed_hosts is forbidden" do
    users(:bartek).update!(title: :captain)
    sign_in_as(users(:bartek))
    get new_event_path
    assert_redirected_to root_path
  end

  test "GET /eventy/nowy as master lists ALL hosts in dropdown" do
    users(:ala).update!(title: :master)
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

  test "POST /eventy as master accepts any host_id" do
    users(:ala).update!(title: :master)
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

  test "GET / does NOT show 'Zaplanuj wydarzenie' button for users without rank" do
    sign_in_as(users(:bartek))
    get root_path
    assert_no_match I18n.t("events.new_event"), response.body
  end

  test "GET / shows enabled 'Zaplanuj wydarzenie' link for master" do
    users(:ala).update!(title: :master)
    get root_path
    assert_select "a[href=?]", new_event_path, text: /#{Regexp.escape(I18n.t("events.new_event"))}/
  end

  test "GET / shows DISABLED 'Zaplanuj wydarzenie' for komendant without managed_hosts" do
    users(:bartek).update!(title: :captain)
    sign_in_as(users(:bartek))
    get root_path
    assert_response :success
    assert_select "span[aria-disabled='true']", text: /#{Regexp.escape(I18n.t("events.new_event"))}/
    assert_match I18n.t("events.new_event_disabled_hint"), response.body
    assert_select "a[href=?]", new_event_path, count: 0
  end

  test "GET / shows enabled 'Zaplanuj wydarzenie' for komendant with managed_hosts" do
    users(:bartek).update!(title: :captain)
    users(:bartek).managed_hosts << hosts(:jan)
    sign_in_as(users(:bartek))
    get root_path
    assert_response :success
    assert_select "a[href=?]", new_event_path, text: /#{Regexp.escape(I18n.t("events.new_event"))}/
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
