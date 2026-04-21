require "test_helper"

class HostsControllerTest < ActionDispatch::IntegrationTest
  test "routes expose admin CRUD URLs for hosts" do
    assert_equal "/organizatorzy/1",               host_path(1)
    assert_equal "/organizatorzy/nowy",            new_host_path
    assert_equal "/organizatorzy/1/edytuj",        edit_host_path(1)
  end

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

  # --- show action -----------------------------------------------------------

  test "GET /organizatorzy/:id requires login" do
    get host_path(hosts(:jan))
    assert_redirected_to login_path
  end

  test "GET /organizatorzy/:id as signed-in user renders host details" do
    sign_in_as(users(:bartek))  # not admin
    get host_path(hosts(:jan))
    assert_response :success
    assert_match hosts(:jan).display_name, response.body
    assert_match hosts(:jan).location,     response.body
  end

  test "GET /organizatorzy/:id shows 'Komendanci' section when host has managers" do
    hosts(:jan).managers << users(:cezary)
    users(:cezary).update!(title: :captain)

    sign_in_as(users(:bartek))
    get host_path(hosts(:jan))
    assert_match I18n.t("hosts.commanders"), response.body
    assert_match users(:cezary).display_name, response.body
  end

  test "GET /organizatorzy/:id hides 'Komendanci' section when host has no managers" do
    sign_in_as(users(:bartek))
    get host_path(hosts(:jan))
    assert_no_match I18n.t("hosts.commanders"), response.body
  end

  test "GET /organizatorzy does NOT show komendant/blokada captions (those belong on show page)" do
    hosts(:jan).managers << users(:cezary)
    users(:cezary).update!(title: :captain)
    HostBlock.create!(user: users(:bartek), host: hosts(:jan))

    sign_in_as(users(:bartek))
    get hosts_path
    assert_no_match(/komendant/, response.body)
    assert_no_match(/zablokowan/, response.body)
  end

  test "GET /organizatorzy links each host to show page" do
    sign_in_as(users(:bartek))
    get hosts_path
    assert_select "a[href=?]", host_path(hosts(:jan))
  end

  test "GET /organizatorzy/:id as non-admin does not show edit link" do
    sign_in_as(users(:bartek))
    get host_path(hosts(:jan))
    assert_no_match %r{/organizatorzy/#{hosts(:jan).id}/edytuj}, response.body
  end

  test "GET /organizatorzy/:id as admin shows edit link" do
    sign_in_as(users(:ala))  # admin
    get host_path(hosts(:jan))
    assert_match %r{/organizatorzy/#{hosts(:jan).id}/edytuj}, response.body
  end

  # --- admin CRUD ------------------------------------------------------------

  test "GET /organizatorzy/nowy as non-admin redirects" do
    sign_in_as(users(:bartek))
    get new_host_path
    assert_redirected_to root_path
    assert_equal I18n.t("auth.admin_required"), flash[:alert]
  end

  test "GET /organizatorzy/nowy as admin renders form" do
    sign_in_as(users(:ala))
    get new_host_path
    assert_response :success
    assert_match I18n.t("admin.hosts.new_title"), response.body
  end

  test "POST /organizatorzy as admin creates host and redirects to show" do
    sign_in_as(users(:ala))
    assert_difference -> { Host.count }, 1 do
      post hosts_path, params: { host: {
        first_name: "Nowy", last_name: "Organizator",
        email: "nowy-host@example.com", location: "Testowa 1, Kraków"
      } }
    end
    created = Host.find_by(email: "nowy-host@example.com")
    assert_redirected_to host_path(created)
    assert_equal I18n.t("admin.hosts.created"), flash[:notice]
  end

  test "POST /organizatorzy as non-admin is rejected" do
    sign_in_as(users(:bartek))
    assert_no_difference -> { Host.count } do
      post hosts_path, params: { host: {
        first_name: "X", last_name: "Y", email: "x@y.pl", location: "Z"
      } }
    end
    assert_redirected_to root_path
  end

  test "PATCH /organizatorzy/:id as admin updates fields" do
    sign_in_as(users(:ala))
    patch host_path(hosts(:jan)), params: { host: {
      first_name: "Janusz", email: "janusz@example.com", location: "Nowa 5, Warszawa"
    } }
    jan = hosts(:jan).reload
    assert_equal "Janusz",                jan.first_name
    assert_equal "janusz@example.com",    jan.email
    assert_equal "Nowa 5, Warszawa",      jan.location
    assert_redirected_to host_path(jan)
  end

  test "PATCH /organizatorzy/:id as non-admin is rejected" do
    sign_in_as(users(:bartek))
    patch host_path(hosts(:jan)), params: { host: { first_name: "Z" } }
    assert_not_equal "Z", hosts(:jan).reload.first_name
    assert_redirected_to root_path
  end

  test "PATCH /organizatorzy/:id with invalid email re-renders form" do
    sign_in_as(users(:ala))
    patch host_path(hosts(:jan)), params: { host: { email: "nie-email" } }
    assert_response :unprocessable_content
  end

  # --- phone -----------------------------------------------------------------

  test "POST /organizatorzy as admin saves phone when provided" do
    sign_in_as(users(:ala))
    post hosts_path, params: { host: {
      first_name: "Z", last_name: "Telefonem",
      location: "Wieś 1", phone: "+48 111 222 333"
    } }
    assert_equal "+48 111 222 333", Host.find_by(last_name: "Telefonem").phone
  end

  test "PATCH /organizatorzy/:id as admin updates phone" do
    sign_in_as(users(:ala))
    patch host_path(hosts(:jan)), params: { host: { phone: "600 700 800" } }
    assert_equal "600 700 800", hosts(:jan).reload.phone
  end

  test "PATCH /organizatorzy/:id as admin can clear phone by sending blank" do
    hosts(:jan).update!(phone: "600 700 800")
    sign_in_as(users(:ala))
    patch host_path(hosts(:jan)), params: { host: { phone: "" } }
    assert_nil hosts(:jan).reload.phone
  end

  test "GET /organizatorzy/:id renders phone as tel: link when present" do
    hosts(:jan).update!(phone: "+48 600 700 800")
    sign_in_as(users(:bartek))
    get host_path(hosts(:jan))
    assert_response :success
    assert_match "+48 600 700 800", response.body
    assert_select "a[href=?]", "tel:+48 600 700 800"
    assert_match "Telefon", response.body
  end

  test "GET /organizatorzy/:id shows 'Nie podano' for phone when blank" do
    hosts(:jan).update!(phone: nil)
    sign_in_as(users(:bartek))
    get host_path(hosts(:jan))
    assert_response :success
    assert_match "Telefon", response.body
    assert_match "Nie podano", response.body
    assert_select "a[href^=?]", "tel:", count: 0
  end

  test "GET /organizatorzy/:id renders email as mailto: link when present" do
    sign_in_as(users(:bartek))
    get host_path(hosts(:jan))
    assert_response :success
    assert_select "a[href=?]", "mailto:#{hosts(:jan).email}", text: hosts(:jan).email
  end

  test "GET /organizatorzy/:id shows 'Nie podano' instead of mailto when host has no email" do
    hosts(:jan).update!(email: nil)
    sign_in_as(users(:bartek))
    get host_path(hosts(:jan))
    assert_response :success
    assert_match "Nie podano", response.body
    assert_select "a[href^=?]", "mailto:", count: 0
  end
end
