class PromotionMailer < ApplicationMailer
  def notify
    @participation = params[:participation]
    @event = @participation.event
    @user  = @participation.user

    return if recipient_disabled?(@user)

    mail to: @user.email, subject: "Awansowałeś na listę potwierdzonych"
  end
end
