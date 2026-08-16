module Event::Reservable
  extend ActiveSupport::Concern

  # Auto-invites for the top rank. The invitee has RESERVATION_WINDOW to accept
  # or decline; the rest of the flow lives in ReservationService.

  RESERVATION_WINDOW = 2.hours + 30.minutes

  included do
    after_create_commit :seed_reservations, if: :upcoming_now?
  end

  private

  # Rezerwacje dla mistrzów siedzą na kampanii, nie na jej sub-eventach.
  def seed_reservations
    return if event_campaign_id?
    ReservationService.seed_on_create(self)
  end
end
