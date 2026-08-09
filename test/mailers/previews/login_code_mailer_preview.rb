class LoginCodeMailerPreview < ActionMailer::Preview
  def notify
    user = User.first || OpenStruct.new(email: "ala@example.com", first_name: "Ala")
    LoginCodeMailer.with(record: user, code: "12345").notify
  end
end
