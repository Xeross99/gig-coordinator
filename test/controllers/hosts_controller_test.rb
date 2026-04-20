require "test_helper"

class HostsControllerTest < ActionDispatch::IntegrationTest
  test "redirects to login when not signed in" do
    get hosts_path
    assert_redirected_to login_path
  end

  test "redirects host users too (index is worker-facing)" do
    sign_in_as(hosts(:jan))
    get hosts_path
    assert_redirected_to login_path
  end

  test "GET index as user lists all hosts with display names" do
    sign_in_as(users(:ala))
    get hosts_path
    assert_response :success
    assert_match hosts(:jan).display_name,  response.body
    assert_match hosts(:anna).display_name, response.body
  end

  test "GET index renders a Google Maps embed per host" do
    sign_in_as(users(:ala))
    get hosts_path
    assert_select "iframe[src*='maps.google.com/maps'][src*='output=embed']", minimum: 2
  end

  test "GET index uses Polish singular when a host has exactly 1 upcoming event" do
    # Fixtures: jan owns gig-coordinators_tomorrow (1), anna owns harvest_next_week (1).
    sign_in_as(users(:ala))
    get hosts_path
    assert_match "chytanie", response.body
    assert_no_match(/chytania\b/, response.body)
    assert_no_match(/chytań\b/,   response.body)
  end

  test "GET index uses Polish 2-4 plural when a host has 2 upcoming events" do
    # Second event for jan — count becomes 2.
    Event.create!(host: hosts(:jan), name: "Drugie", scheduled_at: 3.days.from_now,
                  ends_at: 3.days.from_now + 2.hours, pay_per_person: 100, capacity: 2)

    sign_in_as(users(:ala))
    get hosts_path
    assert_match(/chytania\b/, response.body)  # jan: 2
    assert_match "chytanie",   response.body   # anna still has 1
  end

  test "GET index uses Polish >=5 plural when a host has 5 upcoming events" do
    5.times do |i|
      Event.create!(host: hosts(:jan), name: "E#{i}", scheduled_at: (i + 3).days.from_now,
                    ends_at: (i + 3).days.from_now + 2.hours, pay_per_person: 50, capacity: 2)
    end
    # Note: jan started with 1 (gig-coordinators_tomorrow) → now 6.

    sign_in_as(users(:ala))
    get hosts_path
    assert_match(/chytań\b/, response.body)
  end

  test "GET /organizatorzy/:id requires login" do
    get host_path(hosts(:jan))
    assert_redirected_to login_path
  end

  test "GET /organizatorzy/:id renders host details" do
    sign_in_as(users(:ala))
    get host_path(hosts(:jan))
    assert_response :success
    assert_match hosts(:jan).display_name, response.body
    assert_match hosts(:jan).location,     response.body
  end

  test "GET /organizatorzy/:id shows 'Komendanci' section when host has managers" do
    hosts(:jan).managers << users(:ala)
    users(:ala).update!(title: :captain)

    sign_in_as(users(:bartek))
    get host_path(hosts(:jan))
    assert_match I18n.t("hosts.commanders"), response.body
    assert_match users(:ala).display_name,   response.body
  end

  test "GET /organizatorzy/:id hides 'Komendanci' section when host has no managers" do
    sign_in_as(users(:ala))
    get host_path(hosts(:jan))
    assert_no_match I18n.t("hosts.commanders"), response.body
  end

  test "GET /organizatorzy shows manager count next to hosts that have at least one commander" do
    hosts(:jan).managers << users(:ala)
    users(:ala).update!(title: :captain)

    sign_in_as(users(:bartek))
    get hosts_path
    assert_match "1 komendant", response.body
  end

  test "GET /organizatorzy does not show 'komendant' text for hosts without managers" do
    sign_in_as(users(:ala))
    get hosts_path
    assert_no_match(/komendant/, response.body)
  end

  test "GET /organizatorzy links each host to show page" do
    sign_in_as(users(:ala))
    get hosts_path
    assert_select "a[href=?]", host_path(hosts(:jan))
  end
end
