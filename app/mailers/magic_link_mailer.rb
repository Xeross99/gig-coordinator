class MagicLinkMailer < ApplicationMailer
  def link
    @record = params[:record]
    @token = params[:token]
    @url = verify_magic_link_url(token: @token)
    mail to: @record.email, subject: I18n.t("mailers.magic_link.subject")
  end
end
