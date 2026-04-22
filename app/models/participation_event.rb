class ParticipationEvent < ApplicationRecord
  # Append-only audit log of participation status transitions. One row per
  # meaningful change — lets the host see the full "joined / cancelled /
  # rejoined / ..." timeline instead of just the latest state.
  self.inheritance_column = nil

  belongs_to :participation

  enum :event_type, {
    joined:    0,
    cancelled: 1,
    reserved:  2,
    accepted:  3,
    declined:  4,
    promoted:  5,
    expired:   6
  }
end
