class ApplicationMailer < ActionMailer::Base
  default from: "Gig Coordinator <#{Rails.application.credentials.dig(:google, :user_name) || 'no-reply@chicken.local'}>"
  layout "mailer"

  helper MailerComponentsHelper

  after_action :skip_disabled_recipients

  private

  # A disabled account gets no mail at all - one guard for every mailer, since
  # each one passes its recipient differently and a per-action `return` is easy
  # to forget. It runs after the action because only then is the recipient in one
  # predictable place: `message.to` (a Host address simply matches no User).
  def skip_disabled_recipients
    recipients = Array(message.to).map(&:downcase)

    return if recipients.empty?
    return unless User.where(email: recipients).where.not(disabled_at: nil).exists?

    message.perform_deliveries = false
  end
end
