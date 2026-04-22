require "application_system_test_case"

class LoginFlowTest < ApplicationSystemTestCase
  test "user signs in with a 5-digit code and lands on the feed" do
    user = users(:bartek)
    sign_in_as(user)
    assert_current_path root_path, wait: 5
    assert_text events(:gig-coordinators_tomorrow).name
  end

  test "host signs in with a 5-digit code and lands on the host panel" do
    host = hosts(:jan)
    sign_in_as(host)
    assert_current_path host_root_path, wait: 5
  end

  test "wrong code keeps the user on the verification page with an error" do
    user = users(:bartek)
    visit login_path
    fill_in "login_code[email]", with: user.email
    click_on I18n.t("auth.send_code")
    assert_current_path verify_login_path, wait: 5
    # Burn the real code first so our random 12345 can't accidentally match.
    LoginCode.where(authenticatable_type: "User", authenticatable_id: user.id).delete_all
    # The OTP input is opacity-0 under a pointer-events-none overlay, so
    # Selenium refuses to type into it. Set value via JS, then click the real
    # submit button — a genuine browser click goes through Turbo normally.
    execute_script(<<~JS)
      const input = document.querySelector("input[data-code-input-target='input']");
      input.value = "12345";
      input.form.submit();
    JS
    assert_text I18n.t("auth.invalid_code"), wait: 5
  end
end
