require "test_helper"

class WelcomeMailerTest < ActionMailer::TestCase
  test "notify renders recipient, subject, and both links" do
    user = users(:ala)
    mail = WelcomeMailer.notify(user)

    assert_equal [ user.email ], mail.to
    assert_equal I18n.t("mailers.welcome.subject"), mail.subject

    # Polish chars are quoted-printable in mail.body.encoded, so match against
    # the decoded text part where `pracownika` lands as a literal string.
    text = mail.text_part.decoded
    html = mail.html_part.decoded
    assert_match user.first_name, text
    assert_match "pracownika",   text
    assert_match "/logowanie",    text
    assert_match "/poradnik",     text

    assert_match user.first_name, html
    assert_match "/poradnik",     html
    assert_match "/logowanie",    html
  end

  test "notify accepts a positional user arg (no params/with usage)" do
    # Guard against a regression back to the `.with(record:)` pattern —
    # the callers in User#send_welcome_email use `WelcomeMailer.notify(self)`.
    user = users(:ala)
    mail = WelcomeMailer.notify(user)
    assert_equal [ user.email ], mail.to
  end
end
