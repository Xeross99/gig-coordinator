class Participation < ApplicationRecord
  belongs_to :event
  belongs_to :user

  enum :status, { confirmed: 0, waitlist: 1, cancelled: 2 }

  validates :user_id, uniqueness: { scope: :event_id }

  # Active = not cancelled. Used for uniqueness + broadcasts.
  scope :active, -> { where.not(status: :cancelled) }
end
