class PromotionMailer < ApplicationMailer
  def notify
    @participation = params[:participation]
    @event = @participation.event
    @user  = @participation.user
    mail to: @user.email, subject: I18n.t("mailers.promotion.subject")
  end
end
