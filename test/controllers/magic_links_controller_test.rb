require "test_helper"

class MagicLinksControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "POST /magic_links sends mail for existing user and redirects with flash notice" do
    assert_emails 1 do
      post magic_links_path, params: { magic_link: { email: users(:ala).email } }
    end
    assert_redirected_to login_path
    assert_equal I18n.t("auth.check_email"), flash[:notice]
  end

  test "POST /magic_links sends mail for existing host (case-insensitive)" do
    assert_emails 1 do
      post magic_links_path, params: { magic_link: { email: "JAN@EXAMPLE.COM" } }
    end
    assert_redirected_to login_path
  end

  test "POST /magic_links for unknown email still shows neutral response (no enumeration) and sends no mail" do
    assert_emails 0 do
      post magic_links_path, params: { magic_link: { email: "nobody@example.com" } }
    end
    assert_redirected_to login_path
    assert_equal I18n.t("auth.check_email"), flash[:notice]
  end

  test "GET /login/verify with valid User token logs in and redirects to user home" do
    user = users(:ala)
    token = user.signed_id(purpose: :magic_link, expires_in: 15.minutes)

    get verify_magic_link_path(token: token)
    assert_redirected_to root_path
    assert_equal 1, user.sessions.count
  end

  test "GET /login/verify with valid Host token logs in and redirects to host dashboard" do
    host = hosts(:jan)
    token = host.signed_id(purpose: :magic_link, expires_in: 15.minutes)

    get verify_magic_link_path(token: token)
    assert_redirected_to host_root_path
    assert_equal 1, host.sessions.count
  end

  test "GET /login/verify with bogus token shows invalid_token error" do
    get verify_magic_link_path(token: "not-a-real-token")
    assert_redirected_to login_path
    follow_redirect!
    assert_match I18n.t("auth.invalid_token"), response.body
  end

  test "GET /login/verify with expired token shows invalid_token error" do
    user = users(:ala)
    token = user.signed_id(purpose: :magic_link, expires_in: 1.second)
    travel 2.seconds do
      get verify_magic_link_path(token: token)
    end
    assert_redirected_to login_path
  end

end
