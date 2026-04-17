class LoginCodeMailer < ApplicationMailer
  def notify
    @record = params[:record]
    @code   = params[:code]
    mail to: @record.email, subject: I18n.t("mailers.login_code.subject")
  end
end
