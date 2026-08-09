class EventCampaign < ApplicationRecord
  belongs_to :host
  belongs_to :creator, class_name: "User", optional: true
  has_many :events, dependent: :destroy
  has_many :campaign_participations, dependent: :destroy
  has_many :users, through: :campaign_participations
  has_many :changes_log, class_name: "EventCampaignChange", dependent: :destroy

  accepts_nested_attributes_for :events,
                                allow_destroy: true,
                                reject_if: ->(a) { a[:name].blank? && a[:event_date].blank? }

  attr_accessor :edited_by
  attr_accessor :pre_registered_user_ids

  after_create         :process_pre_registrations
  after_update         :process_pre_registrations
  after_create_commit  :seed_reservations
  after_create_commit  :broadcast_feed_append
  after_create_commit  :notify_new_campaign_subscribers
  after_update_commit  :log_changes
  after_update_commit  :broadcast_feed_replace
  after_update_commit  :refill_on_capacity_increase
  after_update_commit  :demote_on_capacity_decrease
  after_destroy_commit :broadcast_feed_remove

  validates :name, presence: true
  validates :capacity, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :active,    -> { where(completed_at: nil).where("EXISTS (SELECT 1 FROM events WHERE events.event_campaign_id = event_campaigns.id AND events.scheduled_at > ?)", Time.current) }
  scope :completed, -> { where.not(completed_at: nil).order(completed_at: :desc) }

  def to_param
    slug = name.to_s.parameterize
    slug.present? ? "#{id}-#{slug}" : id.to_s
  end

  def completed?
    completed_at.present?
  end

  # Mirror Event#participation_counts — single GROUP BY query, memoized.
  def participation_counts
    @participation_counts ||= campaign_participations.group(:status).count.transform_keys(&:to_s)
  end

  def confirmed_count;  participation_counts.fetch("confirmed", 0); end
  def reserved_count;   participation_counts.fetch("reserved",  0); end
  def waitlist_count;   participation_counts.fetch("waitlist",  0); end

  def slots_taken
    confirmed_count + reserved_count
  end

  def full?
    slots_taken >= capacity
  end

  # Sub-eventy nadchodzące i już-ruszone (mirror Event scopes).
  def upcoming_events
    events.where("scheduled_at > ?", Time.current).order(:scheduled_at)
  end

  def past_events
    events.where("scheduled_at <= ?", Time.current).order(:scheduled_at)
  end

  # Postęp zapisów usera na nadchodzące sub-eventy serii: [zapisane, wszystkie].
  # Zasila kopię pod „Masz miejsce na głównej liście serii" w
  # _campaign_participation_button — widok nie powinien składać tych zapytań sam.
  def sub_event_progress_for(user)
    sub_event_ids = upcoming_events.pluck(:id)
    active_count = user.participations.where(event_id: sub_event_ids).where.not(status: :cancelled).count
    [ active_count, sub_event_ids.size ]
  end

  def participant?(user)
    return false if user.blank?
    campaign_participations.where(user_id: user.id, status: %i[confirmed reserved waitlist]).exists?
  end

  def history_count
    1 +
      CampaignParticipationEvent.joins(:campaign_participation)
                                .where(campaign_participations: { event_campaign_id: id }).count +
      changes_count
  end

  # Mirror Event#roster_data — wszystko w kilku zapytaniach, memoizowane na
  # instancji. Bez `all_users` — roster kampanii nie ma sekcji „Wszyscy
  # pracownicy", więc ładowanie całej tabeli users było martwym kosztem
  # przy każdym broadcaście.
  def roster_data
    @roster_data ||= begin
      all_parts = campaign_participations.includes(user: { photo_attachment: :blob }).order(:position).to_a

      by_status = all_parts.group_by(&:status)

      {
        reserved:               by_status["reserved"]  || [],
        confirmed:              by_status["confirmed"] || [],
        waitlist:               by_status["waitlist"]  || [],
        participations_by_user: all_parts.index_by(&:user_id)
      }
    end
  end

  private

  def broadcast_feed_append
    broadcast_prepend_to(
      :event_campaigns,
      target: "events_list",
      partial: "event_campaigns/event_campaign_card",
      locals: { campaign: self }
    )
  end

  FEED_CARD_FIELDS = %w[name capacity completed_at].freeze

  def broadcast_feed_replace
    return unless saved_changes.keys.intersect?(FEED_CARD_FIELDS)

    broadcast_replace_to(
      :event_campaigns,
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "event_campaigns/event_campaign_card",
      locals: { campaign: self }
    )
  end

  def broadcast_feed_remove
    broadcast_remove_to(:event_campaigns, target: ActionView::RecordIdentifier.dom_id(self))
  end

  def notify_new_campaign_subscribers
    immediate_titles = User.titles.keys - Event::NEW_EVENT_LAGGING_TITLES - Event::NEW_EVENT_EXCLUDED_TITLES
    WebPushNotifier.perform_later(:new_campaign, event_campaign_id: id, titles: immediate_titles)
    WebPushNotifier.set(wait: Event::NEW_EVENT_LAGGING_DELAY)
                   .perform_later(:new_campaign, event_campaign_id: id, titles: Event::NEW_EVENT_LAGGING_TITLES)
  end

  def seed_reservations
    CampaignReservationService.seed_on_create(self)
  end

  def log_changes
    EventCampaignChange::TRACKED_FIELDS.each do |field|
      next unless saved_changes.key?(field)
      prev_v, new_v = saved_changes[field]
      next if prev_v.to_s == new_v.to_s
      changes_log.create!(
        user:           edited_by,
        field:          field,
        previous_value: prev_v.to_s,
        new_value:      new_v.to_s
      )
    end
  end

  # Mirror Event#process_pre_registrations — buduje primary roster z checkboxów.
  # Mistrz Pióra pomijamy (idą przez seed_reservations + accept), zablokowanych
  # u hosta wykluczamy (defense-in-depth, choć kampania nie powinna ich wsadzać).
  def process_pre_registrations
    ids = Array(pre_registered_user_ids).map(&:to_i).uniq.reject(&:zero?)
    return if ids.empty?

    blocked = HostBlock.where(host_id: host_id).pluck(:user_id).to_set
    mistrz_ids = User.mistrz_piora.where(id: ids).pluck(:id).to_set
    existing_ids = campaign_participations.where(user_id: ids).pluck(:user_id).to_set
    ordered = ids.reject { |i| blocked.include?(i) || mistrz_ids.include?(i) || existing_ids.include?(i) }
    return if ordered.empty?

    users = User.where(id: ordered).index_by(&:id)
    open_slots = [ capacity - campaign_participations.holding_slot.count, 0 ].max
    confirmed_ids, waitlist_ids = ordered.first(open_slots), ordered.drop(open_slots)

    next_confirmed_pos = (campaign_participations.confirmed.maximum(:position) || 0) + 1
    next_waitlist_pos  = (campaign_participations.waitlist.maximum(:position)  || 0) + 1

    confirmed_ids.each_with_index do |uid, idx|
      next unless users[uid]
      campaign_participations.create!(user: users[uid], status: :confirmed, position: next_confirmed_pos + idx)
    end
    waitlist_ids.each_with_index do |uid, idx|
      next unless users[uid]
      campaign_participations.create!(user: users[uid], status: :waitlist, position: next_waitlist_pos + idx)
    end
  end

  def refill_on_capacity_increase
    return unless saved_change_to_capacity?
    old_cap, new_cap = saved_change_to_capacity
    return unless new_cap.to_i > old_cap.to_i
    CampaignReservationService.fill_open_slots(self)
  end

  def demote_on_capacity_decrease
    return unless saved_change_to_capacity?
    old_cap, new_cap = saved_change_to_capacity
    return unless new_cap.to_i < old_cap.to_i
    CampaignReservationService.demote_overflow(self)
  end
end
