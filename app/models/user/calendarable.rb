module User::Calendarable
  extend ActiveSupport::Concern

  included do
    before_create :ensure_calendar_token
  end

  def regenerate_calendar_token!
    update!(calendar_token: SecureRandom.hex(20))
  end

  private

  def ensure_calendar_token
    self.calendar_token ||= SecureRandom.hex(20)
  end
end
