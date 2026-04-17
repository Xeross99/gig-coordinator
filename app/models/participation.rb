class Participation < ApplicationRecord
  belongs_to :event
  belongs_to :user

  enum :status, { confirmed: 0, waitlist: 1, cancelled: 2, reserved: 3 }

  validates :user_id, uniqueness: { scope: :event_id }

  # Active = not cancelled. Covers confirmed, waitlist, reserved.
  scope :active,       -> { where.not(status: :cancelled) }
  # Slots held against event capacity: confirmed (accepted) + reserved (awaiting response).
  scope :holding_slot, -> { where(status: %i[confirmed reserved]) }

  # Any change to a participation (create, status flip, destroy) refreshes the
  # event's roster + counts for everyone viewing that event — via controllers,
  # service objects, background jobs, AND `bin/rails runner` scripts. Keeping
  # this on the model means we don't need to remember to broadcast in every
  # code path that touches participations.
  after_commit :broadcast_event_updates, on: %i[create update destroy]

  def reservation_expired?
    reserved? && reserved_until.present? && reserved_until <= Time.current
  end

  private

  def broadcast_event_updates
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
end
