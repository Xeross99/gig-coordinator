require "test_helper"

class MagicLinkMailerTest < ActionMailer::TestCase
  test "link email contains magic link URL and greeting" do
    user = users(:ala)
    token = user.signed_id(purpose: :magic_link, expires_in: 15.minutes)
    mail = MagicLinkMailer.with(record: user, token: token).link

    assert_equal [ user.email ], mail.to
    assert_equal I18n.t("mailers.magic_link.subject"), mail.subject
    assert_includes mail.body.encoded, user.first_name
    assert_match(/\/login\/verify\?token=/, mail.body.encoded)
  end
end
