require "test_helper"

class CompletedEventMailerTest < ActionMailer::TestCase
  test "notify is addressed to user and includes event name" do
    event = events(:gig-coordinators_tomorrow)
    user  = users(:ala)
    p = Participation.create!(event: event, user: user, status: :confirmed, position: 1)

    mail = CompletedEventMailer.with(participation: p).notify
    assert_equal [ user.email ], mail.to
    assert_match event.name, mail.subject
    assert_match event.name, mail.body.encoded
  end
end
