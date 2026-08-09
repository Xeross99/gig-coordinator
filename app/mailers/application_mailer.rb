class ApplicationMailer < ActionMailer::Base
  default from: "Gig Coordinator <#{Rails.application.credentials.dig(:google, :user_name) || 'no-reply@chicken.local'}>"
  layout "mailer"

  # ActionMailer nie wciąga app/helpers automatycznie (inaczej niż kontrolery),
  # więc komponenty (mail_title, mail_paragraph, …) podpinamy jawnie.
  helper MailerComponentsHelper

  private

  # Wyłączone konto = zero maili. Guard w mailerach (nie w call-site'ach),
  # żeby obejmował KAŻDĄ ścieżkę wysyłki. respond_to? — odbiorcą bywa Host,
  # który nie ma pojęcia wyłączania.
  def recipient_disabled?(record)
    record.disabled?
  end
end
