class Event < ApplicationRecord
  RESERVATION_WINDOW = 1.hour

  # Żółtodzioby (najniższa ranga) dostają push o nowym evencie 5 min po reszcie,
  # żeby wyższe rangi miały fory na zapis. Feed / turbo broadcasty lecą real-time
  # dla wszystkich — opóźnienie dotyczy tylko web-pushy.
  NEW_EVENT_LAGGING_TITLES = %w[rookie].freeze
  NEW_EVENT_LAGGING_DELAY  = 5.minutes

  belongs_to :host
  has_many :participations, dependent: :destroy
  has_many :users, through: :participations
  has_many :messages, -> { order(:created_at) }, dependent: :destroy

  # Zapis od razu: virtual attribute set from the event-creation form. Handled
  # in-transaction (after_create, NOT after_create_commit) so the confirmed
  # participations exist before `seed_reservations` fires — `invite_candidates`
  # then naturally excludes them, which enforces "mistrz dodany od razu = brak
  # osobnej rezerwacji dla niego".
  attr_accessor :pre_registered_user_ids

  after_create         :create_pre_registrations
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
  scope :completed, -> { where.not(completed_at: nil).order(scheduled_at: :desc) }

  def to_param
    slug = name.to_s.parameterize
    slug.present? ? "#{id}-#{slug}" : id.to_s
  end

  def completed?
    completed_at.present?
  end

  # Single GROUP BY query, memoized per instance. All count helpers below derive
  # from this — so rendering _counts + _roster triggers one query instead of
  # four (confirmed + reserved + waitlist + slots_taken).
  def participation_counts
    @participation_counts ||= participations.group(:status).count.transform_keys(&:to_s)
  end

  def confirmed_count
    participation_counts.fetch("confirmed", 0)
  end

  def reserved_count
    participation_counts.fetch("reserved", 0)
  end

  def waitlist_count
    participation_counts.fetch("waitlist", 0)
  end

  # Slots held against capacity — accepted + awaiting-response both block the slot.
  def slots_taken
    confirmed_count + reserved_count
  end

  def full?
    slots_taken >= capacity
  end

  # Everything the roster partial needs, loaded in a handful of queries and
  # memoized on the instance. Called from the user+host show pages and from
  # Participation#broadcast_event_updates (on a fresh Event instance each
  # broadcast — memoization helps within a single render).
  def roster_data
    @roster_data ||= begin
      all_users   = User.with_attached_photo.order(title: :desc, last_name: :asc, first_name: :asc).to_a
      users_by_id = all_users.index_by(&:id)

      all_parts = participations.order(:position).to_a
      all_parts.each do |p|
        preloaded = users_by_id[p.user_id]
        p.association(:user).target = preloaded if preloaded
      end

      by_status = all_parts.group_by(&:status)
      {
        reserved:               by_status["reserved"]  || [],
        confirmed:              by_status["confirmed"] || [],
        waitlist:               by_status["waitlist"]  || [],
        all_users:              all_users,
        participations_by_user: all_parts.index_by(&:user_id),
        blocked_user_ids:       HostBlock.where(host_id: host_id).pluck(:user_id).to_set
      }
    end
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

  FEED_CARD_FIELDS = %w[name pay_per_person capacity scheduled_at ends_at completed_at].freeze

  def broadcast_feed_replace
    return unless saved_changes.keys.intersect?(FEED_CARD_FIELDS)

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
    immediate_titles = User.titles.keys - NEW_EVENT_LAGGING_TITLES
    WebPushNotifier.perform_later(:new_event, event_id: id, titles: immediate_titles)
    WebPushNotifier.set(wait: NEW_EVENT_LAGGING_DELAY)
                   .perform_later(:new_event, event_id: id, titles: NEW_EVENT_LAGGING_TITLES)
  end

  def seed_reservations
    ReservationService.seed_on_create(self)
  end

  def create_pre_registrations
    ids = Array(pre_registered_user_ids).map(&:to_i).uniq.reject(&:zero?)
    return if ids.empty?

    blocked = HostBlock.where(host_id: host_id).pluck(:user_id).to_set
    ordered = ids.reject { |i| blocked.include?(i) }
    return if ordered.empty?

    confirmed_ids, waitlist_ids = ordered.first(capacity), ordered.drop(capacity)
    users = User.where(id: ordered).index_by(&:id)

    confirmed_ids.each_with_index do |uid, idx|
      next unless users[uid]
      participations.create!(user: users[uid], status: :confirmed, position: idx + 1)
    end
    waitlist_ids.each_with_index do |uid, idx|
      next unless users[uid]
      participations.create!(user: users[uid], status: :waitlist, position: idx + 1)
    end
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
