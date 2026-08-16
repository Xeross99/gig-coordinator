class PromotionMailer < ApplicationMailer
  def notify
    @participation = params[:participation]
    @event = @participation.event
    @user  = @participation.user

    mail to: @user.email, subject: "Awansowałeś na listę potwierdzonych"
  end
end
