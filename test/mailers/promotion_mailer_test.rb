require "test_helper"

class PromotionMailerTest < ActionMailer::TestCase
  test "notify is addressed to user and mentions event name" do
    event = events(:chickens_tomorrow)
    user  = users(:ala)
    p = Participation.create!(event: event, user: user, status: :confirmed, position: 1)

    mail = PromotionMailer.with(participation: p).notify
    assert_equal [ user.email ], mail.to
    assert_equal "Awansowałeś na listę potwierdzonych", mail.subject
    assert_match event.name, mail.html_part.decoded
  end
end
