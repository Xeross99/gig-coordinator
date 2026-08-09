class ReservationService
  WINDOW = Event::RESERVATION_WINDOW

  # Każdy mistrz_piora dostaje zaproszenie na nowy event — niezależnie od
  # capacity. Capacity ograniczyłaby ich, więc np. event 1-osobowy z 3 mistrzami
  # zaprosiłby tylko jednego, a my chcemy każdemu dać szansę kliknąć
  # „Akceptuję". Pierwszy który kliknie dostaje confirmed; kolejni — gdy
  # confirmed_count osiągnie capacity — lądują na liście rezerwowej (logika
  # w `ParticipationsController#accept`).
  def self.seed_on_create(event)
    with_lock(event) do
      invite_candidates(event).each { |u| invite!(event, u) }
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

  # Capacity dropped below the confirmed headcount — demote the most-recently
  # confirmed users (highest `position`) back to the waitlist until we're at
  # capacity. Demoted users land at the FRONT of the waitlist (existing waitlist
  # is shifted down) — they had a confirmed slot, admin's shrink isn't their
  # fault, so they get priority on re-promotion if capacity grows again.
  def self.demote_overflow(event)
    with_lock(event) do
      overflow = event.participations.confirmed.count - event.capacity
      next if overflow <= 0

      to_demote = event.participations.confirmed.order(position: :desc).limit(overflow).to_a

      # Push existing waitlist back by N to free up positions 1..N at the front.
      event.participations.waitlist.update_all(Arel.sql("position = position + #{overflow.to_i}"))

      # Place demoted in confirmed-position-asc order so whoever was confirmed
      # earliest (lowest confirmed position among demoted) gets waitlist position 1.
      to_demote.sort_by(&:position).each_with_index do |p, idx|
        p.update!(status: :waitlist, position: idx + 1)
      end
      Participation.resequence!(event, :confirmed)
    end
  end

  # Fill every currently-open slot on the event, applying the same "waitlist
  # first, then top-tier invite" rule as `refill_one`. Used when capacity
  # increases mid-event (host bumps 3 → 4) so nobody on the waitlist keeps
  # waiting unnecessarily.
  def self.fill_open_slots(event)
    with_lock(event) do
      loop do
        open = event.capacity - event.participations.holding_slot.count
        break if open <= 0

        next if promote_from_waitlist(event)

        candidate = invite_candidates(event, limit: 1).first
        break unless candidate
        invite!(event, candidate)
      end
    end
  end

  # Cancels a single expired reservation. Called by the per-reservation
  # ReservationExpirationJob scheduled at `reserved_until`. Idempotent — if the
  # user accepted/declined in the meantime it no-ops. The freed slot is refilled
  # by Participation#refill_after_cancellation (reserved→cancelled ⇒ refill_one).
  def self.expire_one!(participation)
    event = participation.event
    with_lock(event) do
      fresh = event.participations.find_by(id: participation.id)
      next unless fresh&.reserved?
      next unless fresh.reserved_until.present? && fresh.reserved_until <= Time.current

      fresh.cancellation_reason = :expired
      fresh.update!(status: :cancelled, reserved_until: nil)
    end
  end

  # Safety-net sweep — NOT scheduled anymore (each reservation has its own
  # expiration job). Kept for manual console use if scheduled jobs ever get lost.
  def self.expire_stale!
    Participation.reserved.where("reserved_until <= ?", Time.current)
                 .includes(:event).find_each { |p| expire_one!(p) }
  end

  # --- internals ---

  # Picks invitees from the `mistrz_piora` tier ONLY — no cascade down.
  # If no mistrz_piora exists (or all are already participating / blocked),
  # the slot stays open. Regular users can still grab it via the feed.
  # `limit:` opcjonalny — `seed_on_create` woła bez limitu (zaprasza
  # wszystkich), `refill_one`/`fill_open_slots` z `limit: 1`.
  def self.invite_candidates(event, limit: nil)
    blocked_ids = HostBlock.where(host_id: event.host_id).pluck(:user_id)
    scope = User.enabled.mistrz_piora
                .where.not(id: event.participations.pluck(:user_id) + blocked_ids)
                .order(:id)
    limit ? scope.limit(limit) : scope
  end

  def self.invite!(event, user)
    pos = (event.participations.holding_slot.maximum(:position) || 0) + 1
    event.participations.create!(
      user: user, status: :reserved, position: pos,
      reserved_until: Time.current + WINDOW
    )
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
    Participation.resequence!(event, :waitlist)
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
