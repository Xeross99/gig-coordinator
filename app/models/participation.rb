class Participation < ApplicationRecord
  belongs_to :event
  belongs_to :user

  enum :status, { confirmed: 0, waitlist: 1, cancelled: 2, reserved: 3 }

  validates :user_id, uniqueness: { scope: :event_id }

  # Active = not cancelled. Covers confirmed, waitlist, reserved.
  scope :active,       -> { where.not(status: :cancelled) }
  # Slots held against event capacity: confirmed (accepted) + reserved (awaiting response).
  scope :holding_slot, -> { where(status: %i[confirmed reserved]) }

  def reservation_expired?
    reserved? && reserved_until.present? && reserved_until <= Time.current
  end
end
