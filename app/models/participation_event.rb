class ParticipationEvent < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :participation

  enum :event_type, {
    joined:           0,
    cancelled:        1,
    reserved:         2,
    accepted:         3,
    declined:         4,
    promoted:         5,
    expired:          6,
    joined_waitlist:  7,
    swapped_in:       8,
    swapped_out:      9
  }
end
