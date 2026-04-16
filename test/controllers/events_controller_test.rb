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

  test "GET / filters by host_id" do
    get root_path(host_id: hosts(:jan).id)
    assert_match events(:gig-coordinators_tomorrow).name, response.body
    assert_no_match events(:harvest_next_week).name, response.body
  end

  test "GET /events/:id shows event with host details and map iframe" do
    event = events(:gig-coordinators_tomorrow)
    get event_path(event)
    assert_response :success
    assert_match event.name, response.body
    assert_match hosts(:jan).display_name, response.body
    assert_select "iframe[src*='maps.google.com/maps'][src*='output=embed']"
  end
end
