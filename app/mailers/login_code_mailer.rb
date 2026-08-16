class LoginCodeMailer < ApplicationMailer
  def notify
    @record = params[:record]
    @code   = params[:code]

    mail to: @record.email, subject: "Twój kod logowania"
  end
end
