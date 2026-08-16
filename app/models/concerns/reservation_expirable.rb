module ReservationExpirable
  extend ActiveSupport::Concern

  included do
    after_commit :schedule_reservation_expiration, on: %i[create update]
  end

  private

  def schedule_reservation_expiration
    return unless reserved? && reserved_until.present?
    return unless previously_new_record? || saved_change_to_reserved_until?

    ReservationExpirationJob.set(wait_until: reserved_until).perform_later(expiration_job_key => id)
  end

  # ReservationExpirationJob takes one keyword per model - `participation_id:`
  # or `campaign_participation_id:` - matching the model name. A model included
  # here without its keyword in the job fails loudly on ArgumentError.
  def expiration_job_key
    :"#{self.class.model_name.param_key}_id"
  end
end
