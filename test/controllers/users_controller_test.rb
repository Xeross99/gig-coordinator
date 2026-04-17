require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
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
end
