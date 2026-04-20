require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "routes expose admin CRUD URLs for users" do
    assert_equal "/pracownicy/nowy",           new_user_path
    assert_equal "/pracownicy/1/edytuj",       edit_user_path(1)
  end

  test "redirects to login when not signed in" do
    get users_path
    assert_redirected_to login_path
  end

  test "redirects host users (index is worker-facing)" do
    sign_in_as(hosts(:jan))
    get users_path
    assert_redirected_to login_path
  end

  test "GET index as user lists all users with display names + titles" do
    sign_in_as(users(:ala))
    get users_path
    assert_response :success
    assert_match users(:ala).display_name,    response.body
    assert_match users(:bartek).display_name, response.body
  end

  test "catch counts include confirmed participations on completed events only" do
    # Controller runs this exact query:
    #   Participation.confirmed.joins(:event).where.not(events: { completed_at: nil })
    #                .group(:user_id).count
    # We mirror it directly to guard the behavior without depending on assigns.
    event = events(:gig-coordinators_tomorrow)
    done = Event.create!(host: hosts(:jan), name: "Zakonczone",
                         scheduled_at: 2.days.ago, ends_at: 2.days.ago + 2.hours,
                         pay_per_person: 100, capacity: 4,
                         completed_at: 1.day.ago)
    Participation.create!(event: done,  user: users(:ala),    status: :confirmed, position: 1)
    Participation.create!(event: event, user: users(:bartek), status: :confirmed, position: 1)  # not completed
    Participation.create!(event: done,  user: users(:cezary), status: :cancelled, position: 0)

    counts = Participation.confirmed
                          .joins(:event)
                          .where.not(events: { completed_at: nil })
                          .group(:user_id)
                          .count

    assert_equal 1, counts[users(:ala).id]
    assert_nil   counts[users(:bartek).id]
    assert_nil   counts[users(:cezary).id]
  end

  test "GET index orders by title desc then last_name" do
    users(:ala).update!(title: :master)        # rank 3
    users(:bartek).update!(title: :member)   # rank 1
    users(:cezary).update!(title: :rookie)       # rank 0

    sign_in_as(users(:ala))
    get users_path

    # Use position in rendered body as a proxy for ordering.
    body = response.body
    assert body.index(users(:ala).display_name) < body.index(users(:bartek).display_name)
    assert body.index(users(:bartek).display_name) < body.index(users(:cezary).display_name)
  end

  # --- show action -----------------------------------------------------------

  test "GET /pracownicy/:id requires login" do
    get user_path(users(:ala))
    assert_redirected_to login_path
  end

  test "GET /pracownicy/:id as host redirects (worker-facing area)" do
    sign_in_as(hosts(:jan))
    get user_path(users(:ala))
    assert_redirected_to login_path
  end

  test "GET /pracownicy/:id shows the user's display_name, email, rank, and catches count" do
    users(:ala).update!(title: :master)

    # Seed one completed-event confirmed participation so the catches count is > 0.
    done = Event.create!(host: hosts(:jan), name: "Zakonczone",
                         scheduled_at: 2.days.ago, ends_at: 2.days.ago + 2.hours,
                         pay_per_person: 100, capacity: 4,
                         completed_at: 1.day.ago)
    Participation.create!(event: done, user: users(:ala), status: :confirmed, position: 1)

    sign_in_as(users(:bartek))
    get user_path(users(:ala))
    assert_response :success
    assert_match users(:ala).display_name,            response.body
    assert_match users(:ala).email,                   response.body
    assert_match I18n.t("user.titles.master"),  response.body
    assert_match "Zaliczone łapania",                 response.body
  end

  test "GET /pracownicy/:id lists upcoming participations" do
    event = events(:gig-coordinators_tomorrow)
    Participation.create!(event: event, user: users(:ala), status: :confirmed, position: 1)

    sign_in_as(users(:bartek))
    get user_path(users(:ala))
    assert_match event.name, response.body
  end

  test "GET /pracownicy/:id 404s for a non-existent user" do
    sign_in_as(users(:ala))
    get user_path(id: 999_999)
    assert_response :not_found
  end

  test "GET /pracownicy/:id shows 'Zarządza' section with linked hosts for a komendant" do
    users(:cezary).update!(title: :captain)
    users(:cezary).managed_hosts << hosts(:jan)

    sign_in_as(users(:bartek))
    get user_path(users(:cezary))
    assert_response :success
    assert_match I18n.t("user.manages"),     response.body
    assert_match hosts(:jan).display_name,   response.body
  end

  test "GET /pracownicy/:id hides 'Zarządza' section when user has no managed_hosts" do
    sign_in_as(users(:bartek))
    get user_path(users(:cezary))
    assert_no_match I18n.t("user.manages"), response.body
  end

  test "GET /pracownicy/:id shows 'Zarządza wszystkimi' section with ALL hosts for master" do
    users(:cezary).update!(title: :master)

    sign_in_as(users(:bartek))
    get user_path(users(:cezary))
    assert_response :success
    assert_match I18n.t("user.manages_all"),  response.body
    assert_match hosts(:jan).display_name,    response.body
    assert_match hosts(:anna).display_name,   response.body
  end

  # --- admin CRUD ------------------------------------------------------------

  test "GET /pracownicy/nowy requires login" do
    get new_user_path
    assert_redirected_to login_path
  end

  test "GET /pracownicy/nowy as non-admin user redirects with alert" do
    sign_in_as(users(:bartek))  # not admin
    get new_user_path
    assert_redirected_to root_path
    assert_equal I18n.t("auth.admin_required"), flash[:alert]
  end

  test "GET /pracownicy/nowy as host redirects (hosts can't be admins)" do
    sign_in_as(hosts(:jan))
    get new_user_path
    assert_redirected_to login_path
  end

  test "GET /pracownicy/nowy as admin renders form" do
    sign_in_as(users(:ala))  # admin
    get new_user_path
    assert_response :success
    assert_match I18n.t("admin.users.new_title"), response.body
  end

  test "POST /pracownicy as admin creates user and redirects to show" do
    sign_in_as(users(:ala))
    assert_difference -> { User.count }, 1 do
      post users_path, params: { user: {
        first_name: "Nowy", last_name: "Pracownik",
        email: "nowy@example.com", title: "rookie"
      } }
    end
    created = User.find_by(email: "nowy@example.com")
    assert_redirected_to user_path(created)
    assert_equal I18n.t("admin.users.created"), flash[:notice]
  end

  test "POST /pracownicy as non-admin is rejected" do
    sign_in_as(users(:bartek))
    assert_no_difference -> { User.count } do
      post users_path, params: { user: { first_name: "X", last_name: "Y", email: "x@y.pl" } }
    end
    assert_redirected_to root_path
  end

  test "POST /pracownicy cannot set admin=true via params" do
    sign_in_as(users(:ala))
    post users_path, params: { user: {
      first_name: "Zuch", last_name: "Admin",
      email: "zuch@example.com", admin: true
    } }
    assert_equal false, User.find_by(email: "zuch@example.com").admin
  end

  test "GET /pracownicy/:id/edytuj as admin renders form" do
    sign_in_as(users(:ala))
    get edit_user_path(users(:bartek))
    assert_response :success
    assert_match users(:bartek).display_name, response.body
    assert_match I18n.t("admin.users.edit_title"), response.body
  end

  test "GET /pracownicy/:id/edytuj as non-admin redirects" do
    sign_in_as(users(:bartek))
    get edit_user_path(users(:cezary))
    assert_redirected_to root_path
  end

  test "PATCH /pracownicy/:id as admin updates fields and redirects to show" do
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: {
      first_name: "Bartłomiej", email: "bartlomiej@example.com", title: "master"
    } }
    bartek = users(:bartek).reload
    assert_equal "Bartłomiej",         bartek.first_name
    assert_equal "bartlomiej@example.com", bartek.email
    assert_equal "master",       bartek.title
    assert_redirected_to user_path(bartek)
  end

  test "PATCH /pracownicy/:id cannot flip admin flag via params" do
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: { admin: true } }
    assert_equal false, users(:bartek).reload.admin
  end

  test "PATCH /pracownicy/:id with invalid email re-renders form" do
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: { email: "nie-email" } }
    assert_response :unprocessable_content
  end

  test "POST /pracownicy with duplicate first+last name pair as admin re-renders form" do
    User.create!(first_name: "Istniejacy", last_name: "Ktos", email: "ist@example.com")
    sign_in_as(users(:ala))
    assert_no_difference -> { User.count } do
      post users_path, params: { user: {
        first_name: "Istniejacy", last_name: "Ktos", email: "inny@example.com"
      } }
    end
    assert_response :unprocessable_content
  end

  # --- phone -----------------------------------------------------------------

  test "POST /pracownicy as admin saves phone when provided" do
    sign_in_as(users(:ala))
    post users_path, params: { user: {
      first_name: "Z", last_name: "Telefonem",
      email: "ztel@example.com", phone: "+48 123 456 789"
    } }
    assert_equal "+48 123 456 789", User.find_by(email: "ztel@example.com").phone
  end

  test "PATCH /pracownicy/:id as admin updates phone" do
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: { phone: "500 600 700" } }
    assert_equal "500 600 700", users(:bartek).reload.phone
  end

  test "PATCH /pracownicy/:id as admin can clear phone by sending blank" do
    users(:bartek).update!(phone: "123 456 789")
    sign_in_as(users(:ala))
    patch user_path(users(:bartek)), params: { user: { phone: "" } }
    assert_nil users(:bartek).reload.phone
  end

  test "GET /pracownicy/:id renders phone as tel: link when present" do
    users(:bartek).update!(phone: "+48 500 600 700")
    sign_in_as(users(:cezary))
    get user_path(users(:bartek))
    assert_response :success
    assert_match "+48 500 600 700", response.body
    assert_select "a[href=?]", "tel:+48 500 600 700"
    assert_match "Telefon", response.body
  end

  test "GET /pracownicy/:id shows 'Nie podano' for phone when blank" do
    users(:bartek).update!(phone: nil)
    sign_in_as(users(:cezary))
    get user_path(users(:bartek))
    assert_response :success
    assert_match "Telefon", response.body
    assert_match "Nie podano", response.body
    assert_select "a[href^=?]", "tel:", count: 0
  end

  test "GET /pracownicy/:id renders email as mailto: link" do
    sign_in_as(users(:cezary))
    get user_path(users(:bartek))
    assert_response :success
    assert_select "a[href=?]", "mailto:#{users(:bartek).email}", text: users(:bartek).email
  end
end
