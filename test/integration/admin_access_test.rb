require "test_helper"

class AdminAccessTest < ActionDispatch::IntegrationTest
  test "admin edits a user's name + email and sees updated values on show page" do
    sign_in_as(users(:ala))

    get edit_user_path(users(:bartek))
    assert_response :success

    patch user_path(users(:bartek)), params: { user: {
      first_name: "Bartłomiej",
      email:      "bartlomiej@example.com"
    } }
    assert_redirected_to user_path(users(:bartek))
    follow_redirect!

    assert_match "Bartłomiej",             response.body
    assert_match "bartlomiej@example.com", response.body
  end

  test "admin creates a host from the UI, then edits it" do
    sign_in_as(users(:ala))

    assert_difference -> { Host.count }, 1 do
      post hosts_path, params: { host: {
        first_name: "Aniela", last_name: "Gospodyni",
        email: "aniela@example.com", location: "Leśna 7, Zakopane"
      } }
    end
    created = Host.find_by(email: "aniela@example.com")
    assert_redirected_to host_path(created)
    follow_redirect!
    assert_match "Aniela Gospodyni", response.body
    assert_match "Leśna 7",          response.body

    patch host_path(created), params: { host: { location: "Morska 2, Sopot" } }
    follow_redirect!
    assert_match "Morska 2", response.body
  end

  test "non-admin sees the user index without the Dodaj button" do
    sign_in_as(users(:bartek))
    get users_path
    assert_response :success
    assert_no_match I18n.t("admin.users.add_button"), response.body
  end

  test "non-admin sees the host show page without the Edytuj link" do
    sign_in_as(users(:bartek))
    get host_path(hosts(:jan))
    assert_response :success
    assert_no_match I18n.t("admin.hosts.edit_link"), response.body
  end

  test "non-admin cannot reach admin URLs directly" do
    sign_in_as(users(:bartek))

    get new_user_path
    assert_redirected_to root_path

    get edit_host_path(hosts(:jan))
    assert_redirected_to root_path

    post users_path, params: { user: { first_name: "X", last_name: "Y", email: "x@y.pl" } }
    assert_redirected_to root_path
  end
end
