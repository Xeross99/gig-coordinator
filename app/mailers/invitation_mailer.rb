class InvitationMailer < ApplicationMailer
  def notify
    @event = params[:event]
    @user  = params[:user]

    @deadline = Event::RESERVATION_WINDOW.from_now

    mail to: @user.email, subject: "Zaproszenie na #{@event.name} - masz 2,5 godziny na potwierdzenie"
  end
end
