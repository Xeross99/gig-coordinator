class WelcomeMailerPreview < ActionMailer::Preview
  def notify_user
    user = User.first || OpenStruct.new(email: "ala@example.com", first_name: "Ala")
    WelcomeMailer.with(record: user).notify
  end

  def notify_host
    host = Host.first || OpenStruct.new(email: "organizator@example.com", first_name: "Jan")
    WelcomeMailer.with(record: host).notify
  end
end
