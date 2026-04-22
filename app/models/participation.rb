class Participation < ApplicationRecord
  belongs_to :event
  belongs_to :user
  has_many :participation_events, dependent: :delete_all

  enum :status, { confirmed: 0, waitlist: 1, cancelled: 2, reserved: 3 }

  validates :user_id, uniqueness: { scope: :event_id }

  # Active = not cancelled. Covers confirmed, waitlist, reserved.
  scope :active,       -> { where.not(status: :cancelled) }
  # Slots held against event capacity: confirmed (accepted) + reserved (awaiting response).
  scope :holding_slot, -> { where(status: %i[confirmed reserved]) }

  # Transient flag set by ReservationService.expire_stale! so the after_commit
  # logger can distinguish an automatic expiration from a user-initiated decline
  # (both land on :cancelled via reserved→cancelled).
  attr_accessor :cancellation_reason

  # Any change to a participation (create, status flip, destroy) refreshes the
  # event's roster + counts for everyone viewing that event — via controllers,
  # service objects, background jobs, AND `bin/rails runner` scripts. Keeping
  # this on the model means we don't need to remember to broadcast in every
  # code path that touches participations.
  after_commit :broadcast_event_updates, on: %i[create update destroy]
  after_commit :log_participation_event, on: %i[create update]

  def reservation_expired?
    reserved? && reserved_until.present? && reserved_until <= Time.current
  end

  private

  def broadcast_event_updates
    return unless roster_relevant_change?

    fresh_event = Event.find_by(id: event_id)
    return unless fresh_event  # event may have been destroyed in the same transaction

    Turbo::StreamsChannel.broadcast_replace_to(
      [ fresh_event, :roster ],
      target: ActionView::RecordIdentifier.dom_id(fresh_event, :roster),
      partial: "events/roster",
      locals: { event: fresh_event }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      [ fresh_event, :counts ],
      target: ActionView::RecordIdentifier.dom_id(fresh_event, :counts),
      partial: "events/counts",
      locals: { event: fresh_event }
    )
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

  def classify_transition
    # Create path: `saved_change_to_status` nie mówi prawdy o tym, czy to
    # create czy update — dla create z defaultowym statusem (confirmed = 0)
    # nie ma w ogóle saved_change, a dla create z innym statusem prev jest
    # populowany DB defaultem ("confirmed"), nie nil. Patrzymy na
    # `previously_new_record?` — Rails gwarantuje że w after_commit zwraca
    # true wyłącznie gdy rekord właśnie został utworzony.
    if previously_new_record?
      case status
      when "confirmed", "waitlist" then :joined
      when "reserved"              then :reserved
        # create z :cancelled nie loguje nic — nic „prawdziwego" się nie zadziało
      end
    elsif saved_change_to_status?
      prev_status, new_status = saved_change_to_status
      case [ prev_status, new_status ]
      in [ "cancelled", "confirmed" | "waitlist" ] then :joined
      in [ "waitlist",  "confirmed" ]              then :promoted
      in [ "reserved",  "confirmed" ]              then :accepted
      in [ "reserved",  "cancelled" ]              then cancellation_reason == :expired ? :expired : :declined
      in [ _,           "cancelled" ]              then :cancelled
      else nil
      end
    end
  end
end
