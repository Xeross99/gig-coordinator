class Participation < ApplicationRecord
  include ReservationExpirable

  belongs_to :event
  belongs_to :user
  has_many :participation_events, dependent: :delete_all

  enum :status, { confirmed: 0, waitlist: 1, cancelled: 2, reserved: 3 }

  validates :user_id, uniqueness: { scope: :event_id }

  # Active = not cancelled. Covers confirmed, waitlist, reserved.
  scope :active,       -> { where.not(status: :cancelled) }
  # Slots held against event capacity: confirmed (accepted) + reserved (awaiting response).
  scope :holding_slot, -> { where(status: %i[confirmed reserved]) }

  # Transient flag set by ReservationService.expire_one! so the after_commit
  # logger can distinguish an automatic expiration from a user-initiated decline
  # (both land on :cancelled via reserved→cancelled).
  # `skip_refill` — set by callers that fill the vacated slot themselves with
  # custom ordering (campaign cascade prefers campaign-confirmed waitlisters),
  # so the generic refill_after_cancellation must stand down.
  attr_accessor :cancellation_reason, :swap_transition, :skip_refill

  # Any change to a participation (create, status flip, destroy) refreshes the
  # event's roster + counts for everyone viewing that event — via controllers,
  # service objects, background jobs, AND `bin/rails runner` scripts. Keeping
  # this on the model means we don't need to remember to broadcast in every
  # code path that touches participations.
  after_commit :broadcast_event_updates, on: %i[create update destroy]
  after_commit :log_participation_event, on: %i[create update]
  after_commit :cleanup_carpool_on_cancel, on: %i[update destroy]
  after_commit :expire_swap_proposals_on_status_change, on: :update
  after_commit :refill_after_cancellation, on: :update

  def reservation_expired?
    reserved? && reserved_until.present? && reserved_until <= Time.current
  end

  def self.resequence!(event, status)
    event.participations.where(status: status).order(:position).each_with_index do |p, i|
      p.update_column(:position, i + 1) if p.position != i + 1
    end
  end

  private

  # Every transition into :cancelled frees a slot (or shortens the waitlist) —
  # regardless of WHERE the cancel came from: controller, API, service, sweeper
  # job or a bare `update!(status: :cancelled)` in `rails console`. Keeping the
  # refill here (like the broadcasts) means the roster math can never be
  # forgotten by a new code path.
  #
  # Slot semantics mirror the controllers this replaces:
  # - confirmed → cancelled: promote the oldest waitlister (mailer + push).
  # - reserved  → cancelled: full refill_one (waitlist first, then invite the
  #   next mistrz_piora) — decline/expire semantics.
  # - waitlist  → cancelled: nothing to fill, just close the position gap.
  def refill_after_cancellation
    return if skip_refill || swap_transition
    return unless saved_change_to_status? && status == "cancelled"

    fresh_event = Event.find_by(id: event_id)
    return unless fresh_event
    return if fresh_event.started?

    case saved_change_to_status[0]
    when "confirmed"
      Event.transaction do
        fresh_event.lock!
        ReservationService.promote_from_waitlist(fresh_event)
        Participation.resequence!(fresh_event, :confirmed)
        Participation.resequence!(fresh_event, :waitlist)
      end
    when "reserved"
      ReservationService.refill_one(fresh_event)
      Event.transaction do
        fresh_event.lock!
        Participation.resequence!(fresh_event, :confirmed)
        Participation.resequence!(fresh_event, :waitlist)
      end
    when "waitlist"
      Event.transaction do
        fresh_event.lock!
        Participation.resequence!(fresh_event, :waitlist)
      end
    end
  end

  def broadcast_event_updates
    return unless roster_relevant_change?

    fresh_event = Event.find_by(id: event_id)
    return unless fresh_event  # event may have been destroyed in the same transaction

    # Rendery rostra (default + spersonalizowane) są ciężkie — lecą z kolejki
    # (EventRosterBroadcastJob), żeby nie blokować requestu, który zmienił
    # uczestnictwo.
    EventRosterBroadcastJob.perform_later(event_id: fresh_event.id, counts: true)
  end

  # Skip broadcasts for updates that don't change the roster visually — e.g. a
  # bare `touch` or a `reserved_until` extension. Only status/position flips
  # (and creates/destroys) actually reshape the list + counts.
  def roster_relevant_change?
    return true if destroyed?
    return true if previously_new_record?
    saved_change_to_status? || saved_change_to_position?
  end

  # Append one row to participation_events describing this transition. Inferred
  # from the status change; `reserved → cancelled` is ambiguous (user decline vs
  # sweeper expiration) — ReservationService sets `cancellation_reason = :expired`
  # to disambiguate.
  def log_participation_event
    event_type = classify_transition
    return unless event_type

    participation_events.create!(event_type: event_type)
  end

  # When a user cancels (or their participation is deleted), kill the carpool
  # artifacts they own for this event — their driver offer (which cascades to
  # passenger requests under them) and any passenger requests they made.
  def cleanup_carpool_on_cancel
    cancelled_now = destroyed? || (saved_change_to_status? && status == "cancelled")
    return unless cancelled_now

    CarpoolOffer.where(event_id: event_id, user_id: user_id).destroy_all
    CarpoolRequest.joins(:carpool_offer)
                  .where(user_id: user_id, carpool_offers: { event_id: event_id })
                  .destroy_all
  end

  def expire_swap_proposals_on_status_change
    return unless saved_change_to_status?
    return unless defined?(SwapProposal)

    if status == "confirmed" && !swap_transition
      SwapProposal.pending.where(event_id: event_id, proposer_id: user_id)
                  .update_all(status: SwapProposal.statuses[:expired])
    end

    if status == "cancelled"
      SwapProposal.pending.where(event_id: event_id, proposer_id: user_id)
                  .update_all(status: SwapProposal.statuses[:expired])
      SwapProposal.pending.where(event_id: event_id, target_id: user_id)
                  .update_all(status: SwapProposal.statuses[:expired])
    end
  end

  def classify_transition
    # Create path: `saved_change_to_status` nie mówi prawdy o tym, czy to
    # create czy update — dla create z defaultowym statusem (confirmed = 0)
    # nie ma w ogóle saved_change, a dla create z innym statusem prev jest
    # populowany DB defaultem ("confirmed"), nie nil. Patrzymy na
    # `previously_new_record?` — Rails gwarantuje że w after_commit zwraca
    # true wyłącznie gdy rekord właśnie został utworzony.
    if previously_new_record?
      case status
      when "confirmed" then :joined
      when "waitlist"  then :joined_waitlist
      when "reserved"  then :reserved
        # create z :cancelled nie loguje nic — nic „prawdziwego" się nie zadziało
      end
    elsif saved_change_to_status?
      prev_status, new_status = saved_change_to_status
      case [ prev_status, new_status ]
      in [ "cancelled", "confirmed" ] then :joined
      in [ "cancelled", "waitlist"  ] then :joined_waitlist
      in [ "waitlist",  "confirmed" ] then swap_transition || :promoted
      in [ "reserved",  "confirmed" ] then :accepted
      in [ "reserved",  "cancelled" ] then cancellation_reason == :expired ? :expired : :declined
      in [ _,           "cancelled" ] then swap_transition || :cancelled
      else nil
      end
    end
  end
end
