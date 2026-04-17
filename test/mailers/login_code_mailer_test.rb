require "test_helper"

class LoginCodeMailerTest < ActionMailer::TestCase
  test "notify renders recipient, subject, and 5-digit code" do
    user = users(:ala)
    mail = LoginCodeMailer.with(record: user, code: "12345").notify

    assert_equal [ user.email ], mail.to
    assert_equal I18n.t("mailers.login_code.subject"), mail.subject
    assert_match "12345", mail.body.encoded
    assert_match user.first_name, mail.body.encoded
  end
end
