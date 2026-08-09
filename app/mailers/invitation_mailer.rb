class InvitationMailer < ApplicationMailer
  def notify
    @event    = params[:event]
    @user     = params[:user]

    return if recipient_disabled?(@user)

    @deadline = Event::RESERVATION_WINDOW.from_now

    mail to: @user.email, subject: "Zaproszenie na #{@event.name} - masz 2,5 godziny na potwierdzenie"
  end
end
