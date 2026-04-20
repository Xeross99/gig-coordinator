require "test_helper"

class InfoControllerTest < ActionDispatch::IntegrationTest
  test "GET /poradnik is public (auth layout) for anonymous visitors" do
    get install_guide_path
    assert_response :success
    # Public path — no navbar dropdown is rendered in the auth layout, which
    # confirms the layout switched on signed_in? = false.
    assert_no_match "app-navbar", response.body
  end

  test "GET /poradnik for signed-in user renders in the application layout" do
    sign_in_as(users(:ala))
    get install_guide_path
    assert_response :success
    # Application layout injects the navbar with the user block.
    assert_match "app-navbar",             response.body
    assert_match users(:ala).display_name, response.body
  end

  test "GET /informacje requires login" do
    get info_path
    assert_redirected_to login_path
  end

  test "GET /informacje documents Kapitan event-creation rules" do
    sign_in_as(users(:ala))
    get info_path
    assert_response :success
    # The doc describes both ranks that can plan events and the disabled-button
    # behavior when a komendant has no managed hosts.
    assert_match I18n.t("user.titles.master"),        response.body
    assert_match I18n.t("user.titles.captain"), response.body
    assert_match "wyszarzony",                              response.body
  end
end
