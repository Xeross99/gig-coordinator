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
  end

  # Replace one vacated slot. **Waitlist goes first** — someone already raised
  # their hand and joined the queue, they shouldn't be overtaken by a fresh
  # rank-based invite. Only if no one is waiting do we reach for the next
  # highest-rank user who isn't yet in the event.
  def self.refill_one(event)
    with_lock(event) do
      next unless promote_from_waitlist(event).nil?

      next_candidate = invite_candidates(event, limit: 1).first
      invite!(event, next_candidate) if next_candidate
    end
  end

  # Sweeper — finds expired reservations, cancels them, and refills each slot
  # with the same "waitlist first" rule. Called by ReservationExpirationJob.
  def self.expire_stale!
    expired = Participation.reserved.where("reserved_until <= ?", Time.current).includes(:event)
    expired.find_each do |p|
      with_lock(p.event) { p.update!(status: :cancelled, reserved_until: nil) }
      refill_one(p.event)
    end
  end

  # --- internals ---

  # Picks invitees from the currently-highest-rank tier of users who aren't
  # already in the event. Deliberately NOT cascading through lower ranks on the
  # initial seed — only the top rank gets pre-booked. Lower ranks only get a
  # chance when a reservation is declined/expired (refill_one is called with a
  # smaller pool and the next tier becomes the "top").
  def self.invite_candidates(event, limit:)
    pool = User.where.not(id: event.participations.pluck(:user_id))
    top_title = pool.maximum(:title)
    return User.none if top_title.nil?

    pool.where(title: top_title).order(:id).limit(limit)
  end

  def self.invite!(event, user)
    pos = (event.participations.reserved.maximum(:position) || 0) + 1
    event.participations.create!(
      user: user, status: :reserved, position: pos,
      reserved_until: Time.current + WINDOW
    )
    InvitationMailer.with(event: event, user: user).notify.deliver_later
    WebPushNotifier.perform_later(:invitation, event_id: event.id, user_id: user.id)
    # Replace the generic feed card with one that shows the pending badge for THIS
    # invitee only (the global :events broadcast already appended the plain card).
    Turbo::StreamsChannel.broadcast_replace_to(
      [ user, :events ],
      target: ActionView::RecordIdentifier.dom_id(event),
      partial: "events/event_card",
      locals: { event: event, pending_reservation: true }
    )
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
