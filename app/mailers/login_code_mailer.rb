class LoginCodeMailer < ApplicationMailer
  def notify
    @record = params[:record]
    @code   = params[:code]

    return if recipient_disabled?(@record)

    mail to: @record.email, subject: "Twój kod logowania"
  end
end
