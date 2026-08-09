require "test_helper"

class LoginCodeMailerTest < ActionMailer::TestCase
  test "notify renders recipient, subject, and 5-digit code" do
    user = users(:ala)
    mail = LoginCodeMailer.with(record: user, code: "12345").notify

    assert_equal [ user.email ], mail.to
    assert_equal "Twój kod logowania", mail.subject
    assert_match "12345", mail.html_part.decoded
    assert_match user.first_name, mail.html_part.decoded
  end
end
