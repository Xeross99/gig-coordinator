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
end
