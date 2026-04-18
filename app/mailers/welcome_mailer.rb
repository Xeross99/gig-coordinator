class WelcomeMailer < ApplicationMailer
  def notify(user)
    @user      = user
    @url       = login_url
    @guide_url = install_guide_url
    mail to: @user.email, subject: I18n.t("mailers.welcome.subject")
  end
end
