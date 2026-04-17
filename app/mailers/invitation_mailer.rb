class InvitationMailer < ApplicationMailer
  def notify
    @event    = params[:event]
    @user     = params[:user]
    @deadline = Event::RESERVATION_WINDOW.from_now
    mail to: @user.email, subject: I18n.t("mailers.invitation.subject", event: @event.name)
  end
end
