class LoginCode < ApplicationRecord
  MAX_ATTEMPTS = 5
  EXPIRY       = 15.minutes

  belongs_to :authenticatable, polymorphic: true

  validates :code, presence: true, format: { with: /\A\d{5}\z/ }
  validates :expires_at, presence: true

  scope :active, -> { where(used_at: nil).where("expires_at > ?", Time.current).where("attempts < ?", MAX_ATTEMPTS) }

  scope :for, ->(record) {
    where(authenticatable_type: record.class.polymorphic_name, authenticatable_id: record.id)
  }

  def self.generate_for(record, request: nil)
    transaction do
      self.for(record).active.update_all(used_at: Time.current)
      create!(
        authenticatable: record,
        code:            format("%05d", SecureRandom.random_number(100_000)),
        expires_at:      EXPIRY.from_now,
        ip_address:      request&.remote_ip,
        user_agent:      request&.user_agent
      )
    end
  end

  def self.consume(record, submitted_code)
    submitted = submitted_code.to_s
    match = self.for(record).active.find_by(code: submitted)
    if match
      match.update!(used_at: Time.current)
      return match
    end

    self.for(record).active.each do |code|
      new_attempts = code.attempts + 1
      if new_attempts >= MAX_ATTEMPTS
        code.update!(attempts: new_attempts, used_at: Time.current)
      else
        code.update!(attempts: new_attempts)
      end
    end
    nil
  end
end
