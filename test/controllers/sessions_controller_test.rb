require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "GET /login renders login form" do
    get login_path
    assert_response :success
    assert_select "form[action=?]", magic_links_path
    assert_select "input[type=email][name='magic_link[email]']"
  end

  test "DELETE /session destroys session and redirects to login" do
    sign_in_as(users(:ala))
    assert_equal 1, Session.count
    delete session_path
    assert_redirected_to login_path
    assert_equal 0, Session.count
  end

  test "DELETE /session is no-op when not logged in" do
    delete session_path
    assert_redirected_to login_path
  end

  test "GET /login while logged in redirects to home" do
    sign_in_as(users(:ala))
    get login_path
    assert_redirected_to root_path
  end

  test "GET /login while host logged in redirects to host home" do
    sign_in_as(hosts(:jan))
    get login_path
    assert_redirected_to host_root_path
  end
end
