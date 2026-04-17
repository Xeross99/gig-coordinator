class ReservationService
  WINDOW = Event::RESERVATION_WINDOW

  # Fill all empty slots on a freshly created event with the top-ranked users who
  # don't yet have a participation for this event. Each gets a :reserved status
  # with a deadline WINDOW from now.
  def self.seed_on_create(event)
    with_lock(event) do
      missing = event.capacity - event.participations.holding_slot.count
      next if missing <= 0
      invite_candidates(event, limit: missing).each { |u| invite!(event, u) }
    end
    broadcast(event)
  end

  # Replace one vacated slot. Prefer inviting the next highest-rank user who
  # isn't yet in the event; fall back to promoting from the waitlist if the
  # ranking pool is exhausted.
  def self.refill_one(event)
    with_lock(event) do
      next_candidate = invite_candidates(event, limit: 1).first
      if next_candidate
        invite!(event, next_candidate)
      else
        promote_from_waitlist(event)
      end
    end
    broadcast(event)
  end

  # Sweeper — finds expired reservations, cancels them, and refills each slot.
  # Called by ReservationExpirationJob on a recurring schedule.
  def self.expire_stale!
    expired = Participation.reserved.where("reserved_until <= ?", Time.current).includes(:event)
    expired.find_each do |p|
      Event.transaction do
        p.event.lock!
        p.update!(status: :cancelled, reserved_until: nil)
        candidate = invite_candidates(p.event, limit: 1).first
        if candidate
          invite!(p.event, candidate)
        else
          promote_from_waitlist(p.event)
        end
      end
      broadcast(p.event)
    end
  end

  def self.broadcast(event)
    event.reload
    Turbo::StreamsChannel.broadcast_replace_to(
      [ event, :roster ],
      target: ActionView::RecordIdentifier.dom_id(event, :roster),
      partial: "events/roster",
      locals: { event: event }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      [ event, :counts ],
      target: ActionView::RecordIdentifier.dom_id(event, :counts),
      partial: "events/counts",
      locals: { event: event }
    )
  end

  # --- internals ---

  def self.invite_candidates(event, limit:)
    User
      .where.not(id: event.participations.pluck(:user_id))
      .order(title: :desc, id: :asc)
      .limit(limit)
  end

  def self.invite!(event, user)
    pos = (event.participations.reserved.maximum(:position) || 0) + 1
    event.participations.create!(
      user: user, status: :reserved, position: pos,
      reserved_until: Time.current + WINDOW
    )
    InvitationMailer.with(event: event, user: user).notify.deliver_later
    WebPushNotifier.perform_later(:invitation, event_id: event.id, user_id: user.id)
  end

  def self.promote_from_waitlist(event)
    promoted = event.participations.waitlist.order(:position).first
    return nil unless promoted

    pos = (event.participations.confirmed.maximum(:position) || 0) + 1
    promoted.update!(status: :confirmed, position: pos)
    PromotionMailer.with(participation: promoted).notify.deliver_later
    WebPushNotifier.perform_later(:promotion, participation_id: promoted.id)
    promoted
  end

  def self.with_lock(event, &block)
    Event.transaction do
      event.lock!
      block.call
    end
  end
end
