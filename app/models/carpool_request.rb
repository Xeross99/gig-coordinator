class CarpoolRequest < ApplicationRecord
  belongs_to :carpool_offer
  belongs_to :user

  has_one :event, through: :carpool_offer

  enum :status, { pending: 0, accepted: 1, declined: 2 }

  validates :user_id, uniqueness: { scope: :carpool_offer_id }
  validate  :user_is_not_driver
  validate  :user_is_not_driver_on_event
  validate  :user_is_event_participant
  validate  :seats_available_on_accept

  after_commit :broadcast_roster, on: %i[create update destroy]

  private

  def user_is_not_driver
    return if carpool_offer.blank?
    errors.add(:base, "kierowca nie może zapytać samego siebie") if carpool_offer.user_id == user_id
  end

  # Ktoś kto sam oferuje podwózkę na tym evencie nie może jednocześnie pchać się
  # na miejsce pasażera u innego kierowcy — to sprzeczne zobowiązania (jedna
  # osoba nie jedzie dwoma autami). Najpierw `Zrezygnuj z funkcji kierowcy`,
  # potem proś o podwózkę.
  def user_is_not_driver_on_event
    return if carpool_offer.blank? || user.blank?
    return unless CarpoolOffer.where(event_id: carpool_offer.event_id, user_id: user_id).exists?
    errors.add(:base, "jesteś kierowcą na tym evencie — zrezygnuj najpierw z funkcji kierowcy, żeby poprosić o podwózkę")
  end

  def user_is_event_participant
    return if carpool_offer.blank? || user.blank?
    ev = carpool_offer.event
    return if ev && ev.participations.where(user_id: user_id, status: %i[confirmed reserved waitlist]).exists?
    errors.add(:base, "tylko uczestnicy eventu mogą prosić o podwózkę")
  end

  def seats_available_on_accept
    return unless accepted?
    return unless will_save_change_to_status?
    _prev, new_status = changes["status"]
    return unless new_status == "accepted"

    accepted_count = carpool_offer.carpool_requests.accepted.where.not(id: id).count
    if accepted_count >= CarpoolOffer::SEATS
      errors.add(:base, "brak wolnych miejsc w aucie")
    end
  end

  def broadcast_roster
    ev = Event.find_by(id: carpool_offer&.event_id)
    return unless ev

    Turbo::StreamsChannel.broadcast_replace_to(
      [ ev, :roster ],
      target: ActionView::RecordIdentifier.dom_id(ev, :roster),
      partial: "events/roster",
      locals: { event: ev }
    )
  end
end
