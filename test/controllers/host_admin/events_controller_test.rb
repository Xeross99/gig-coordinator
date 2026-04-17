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
  end
end
