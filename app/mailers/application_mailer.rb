class ApplicationMailer < ActionMailer::Base
  default from: -> { ApplicationMailer.sender_address }
  layout "mailer"

  def self.sender_address
    google = Rails.application.credentials.google
    if google&.user_name.present?
      "GigCoordinator <#{google.user_name}>"
    else
      "no-reply@gig-coordinator.local"
    end
  end
end
