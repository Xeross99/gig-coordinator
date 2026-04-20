class Event < ApplicationRecord
  RESERVATION_WINDOW = 1.hour

  belongs_to :host
  has_many :participations, dependent: :destroy
  has_many :users, through: :participations

  after_create_commit  :broadcast_feed_append,        if: :upcoming_now?
  after_create_commit  :broadcast_visit_to_feed,      if: :upcoming_now?
  after_create_commit  :notify_new_event_subscribers, if: :upcoming_now?
  after_create_commit  :seed_reservations,            if: :upcoming_now?
  after_update_commit  :broadcast_feed_replace
  after_update_commit  :refill_on_capacity_increase
  after_destroy_commit :broadcast_feed_remove

  validates :name, presence: true
  validates :scheduled_at, :ends_at, presence: true
  validates :pay_per_person, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :capacity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate  :ends_at_after_scheduled_at

  scope :upcoming, -> { where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :awaiting_completion, -> { where("ends_at < ? AND completed_at IS NULL", Time.current) }

  def to_param
    slug = name.to_s.parameterize
    slug.present? ? "#{id}-#{slug}" : id.to_s
  end

  def completed?
    completed_at.present?
  end

  def confirmed_count
    participations.confirmed.count
  end

  def reserved_count
    participations.reserved.count
  end

  # Slots held against capacity — accepted + awaiting-response both block the slot.
  def slots_taken
    participations.holding_slot.count
  end

  def waitlist_count
    participations.waitlist.count
  end

  def full?
    slots_taken >= capacity
  end

  private

  def ends_at_after_scheduled_at
    return if ends_at.blank? || scheduled_at.blank?
    errors.add(:ends_at, :must_be_after_start) if ends_at <= scheduled_at
  end

  def upcoming_now?
    scheduled_at.present? && scheduled_at > Time.current
  end

  def broadcast_feed_append
    broadcast_prepend_to(
      :events,
      target: "events_list",
      partial: "events/event_card",
      locals: { event: self }
    )
  end

  def broadcast_feed_replace
    broadcast_replace_to(
      :events,
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "events/event_card",
      locals: { event: self }
    )
  end

  def broadcast_feed_remove
    broadcast_remove_to(:events, target: ActionView::RecordIdentifier.dom_id(self))
  end

  # Push everyone currently on the user feed straight to the new event's page
  # (consumed by the `Turbo.StreamActions.visit` handler in application.js).
  def broadcast_visit_to_feed
    Turbo::StreamsChannel.broadcast_action_to(
      :events,
      action: :visit,
      target: Rails.application.routes.url_helpers.event_path(self)
    )
  end

  def notify_new_event_subscribers
    WebPushNotifier.perform_later(:new_event, event_id: id)
  end

  def seed_reservations
    ReservationService.seed_on_create(self)
  end

  # Host bumped capacity → promote from waitlist (or invite top-tier) to fill
  # the freshly-opened slots. No-op on decrease (we don't evict signed-up workers)
  # or on updates that don't touch capacity.
  def refill_on_capacity_increase
    return unless saved_change_to_capacity?
    old_cap, new_cap = saved_change_to_capacity
    return unless new_cap.to_i > old_cap.to_i
    ReservationService.fill_open_slots(self)
  end
end
