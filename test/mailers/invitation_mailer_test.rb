require "test_helper"

class InvitationMailerTest < ActionMailer::TestCase
  test "notify is addressed to user, mentions event, and includes deadline + link" do
    user  = users(:ala)
    event = events(:chickens_tomorrow)

    mail = InvitationMailer.with(event: event, user: user).notify

    assert_equal [ user.email ], mail.to
    assert_equal "Zaproszenie na #{event.name} - masz 2,5 godziny na potwierdzenie", mail.subject
    # Asercje idą na ZDEKODOWANYCH częściach: w mail.body.encoded polskie znaki
    # są quoted-printable, a miękkie łamanie linii co 76 znaków potrafi rozciąć
    # nazwę eventu na pół — dopasowanie przechodziłoby wtedy zależnie od długości
    # poprzedzającego tekstu.
    [ mail.text_part.decoded, mail.html_part.decoded ].each do |body|
      assert_match event.name,      body
      assert_match user.first_name, body
      assert_match Rails.application.routes.url_helpers.event_url(event, host: "example.com"), body
    end
  end
end
