require "test_helper"

class LoginCodesControllerTest < ActionDispatch::IntegrationTest
  test "POST /kody-logowania generates a code for a known User and sends email" do
    user = users(:ala)
    assert_emails 1 do
      assert_difference -> { LoginCode.count }, 1 do
        post login_codes_path, params: { login_code: { email: user.email.upcase } }
      end
    end
    assert_redirected_to verify_login_path
    assert_equal I18n.t("auth.code_sent"), flash[:notice]

    code = LoginCode.for(user).last
    assert_equal user, code.authenticatable
    assert_match(/\A\d{5}\z/, code.code)
  end

  test "POST /kody-logowania with unknown email: no code, no email, same redirect" do
    assert_no_emails do
      assert_no_difference -> { LoginCode.count } do
        post login_codes_path, params: { login_code: { email: "ghost@example.com" } }
      end
    end
    assert_redirected_to verify_login_path
    assert_equal I18n.t("auth.code_sent"), flash[:notice]
  end

  test "GET /logowanie/weryfikacja without pending email redirects to login" do
    get verify_login_path
    assert_redirected_to login_path
  end

  test "GET /logowanie/weryfikacja with pending email renders the form" do
    post login_codes_path, params: { login_code: { email: users(:ala).email } }
    follow_redirect!
    assert_response :success
    assert_select "input[data-code-input-target='input'][autocomplete='one-time-code']"
    assert_select "div[data-code-input-target='cell']", 5
  end

  test "POST /logowanie/weryfikacja with correct code signs in the user" do
    user = users(:ala)
    post login_codes_path, params: { login_code: { email: user.email } }
    code = LoginCode.for(user).active.last

    assert_difference -> { Session.count }, 1 do
      post verify_login_path, params: { code: code.code }
    end
    assert_redirected_to root_path
    assert_not_nil cookies[:session_token]
    assert_not_nil code.reload.used_at
  end

  test "POST /logowanie/weryfikacja with correct code signs in the host" do
    host = hosts(:jan)
    post login_codes_path, params: { login_code: { email: host.email } }
    code = LoginCode.for(host).active.last

    post verify_login_path, params: { code: code.code }
    assert_redirected_to host_root_path
  end

  test "POST /logowanie/weryfikacja with wrong code shows error and increments attempts" do
    user = users(:ala)
    post login_codes_path, params: { login_code: { email: user.email } }
    code = LoginCode.for(user).active.last

    post verify_login_path, params: { code: "99999" }
    assert_response :unprocessable_entity
    assert_match I18n.t("auth.invalid_code"), flash[:alert]
    assert_equal 1, code.reload.attempts
    assert_nil code.used_at
  end

  test "POST /logowanie/weryfikacja kills the code after 5 wrong attempts" do
    user = users(:ala)
    post login_codes_path, params: { login_code: { email: user.email } }
    code = LoginCode.for(user).active.last

    LoginCode::MAX_ATTEMPTS.times do
      post verify_login_path, params: { code: "99999" }
    end
    code.reload
    assert_equal LoginCode::MAX_ATTEMPTS, code.attempts
    assert_not_nil code.used_at

    # Even with the right code, login fails now
    post verify_login_path, params: { code: code.code }
    assert_response :unprocessable_entity
    assert_nil cookies[:session_token]
  end

  test "digits-only filter strips non-digits from submitted code" do
    user = users(:ala)
    post login_codes_path, params: { login_code: { email: user.email } }
    code = LoginCode.for(user).active.last

    padded = code.code.chars.join("-") # e.g. "1-2-3-4-5"
    post verify_login_path, params: { code: padded }
    assert_redirected_to root_path
  end
end
