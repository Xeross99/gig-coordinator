class WelcomeMailerPreview < ActionMailer::Preview
  def notify
    user = User.first || OpenStruct.new(email: "ala@example.com", first_name: "Ala")
    WelcomeMailer.notify(user)
  end
end
