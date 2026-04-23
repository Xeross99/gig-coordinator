class CarpoolOffer < ApplicationRecord
  SEATS = 4

  belongs_to :event
  belongs_to :user
  has_many :carpool_requests, dependent: :destroy

  validates :user_id, uniqueness: { scope: :event_id }
  validate  :user_is_event_participant
  validate  :user_has_driver_permission

  after_commit :broadcast_roster, on: %i[create update destroy]

  def accepted_requests
    carpool_requests.accepted
  end

  def pending_requests
    carpool_requests.pending
  end

  def seats_taken
    accepted_requests.size
  end

  def seats_left
    SEATS - seats_taken
  end

  def full?
    seats_left <= 0
  end

  private

  def user_is_event_participant
    return if event.blank? || user.blank?
    return if event.participations.where(user_id: user_id, status: %i[confirmed reserved waitlist]).exists?
    errors.add(:base, "tylko uczestnicy eventu mogą zgłosić się jako kierowca")
  end

  def user_has_driver_permission
    return if user.blank?
    errors.add(:base, "nie masz uprawnień kierowcy — poproś administratora") unless user.can_drive?
  end

  def broadcast_roster
    fresh_event = Event.find_by(id: event_id)
    return unless fresh_event

    Turbo::StreamsChannel.broadcast_replace_to(
      [ fresh_event, :roster ],
      target: ActionView::RecordIdentifier.dom_id(fresh_event, :roster),
      partial: "events/roster",
      locals: { event: fresh_event }
    )
  end
end
