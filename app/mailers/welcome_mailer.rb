class WelcomeMailer < ApplicationMailer
  def notify
    @record    = params[:record]
    @is_host   = @record.is_a?(Host)
    @url       = login_url
    @guide_url = install_guide_url
    mail to: @record.email, subject: I18n.t("mailers.welcome.subject")
  end
end
