require "test_helper"

class InvitationMailerTest < ActionMailer::TestCase
  test "notify is addressed to user, mentions event, and includes deadline + link" do
    user  = users(:ala)
    event = events(:gig_coordinators_tomorrow)

    mail = InvitationMailer.with(event: event, user: user).notify

    assert_equal [ user.email ], mail.to
    assert_equal I18n.t("mailers.invitation.subject", event: event.name), mail.subject
    body = mail.body.encoded
    assert_match event.name,       body
    assert_match user.first_name,  body
    # Deadline + event link both present.
    assert_match Rails.application.routes.url_helpers.event_url(event, host: "example.com"), body
  end
end
