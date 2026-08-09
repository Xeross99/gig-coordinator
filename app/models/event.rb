class Event < ApplicationRecord
  RESERVATION_WINDOW = 2.hours + 30.minutes

  # Pachołkowie (praktykanci) dostają push o nowym zleceniu 5 min po wyższych
  # rangach — wyższe mają wtedy fory na zapis. Żółtodziób w ogóle nie dostaje
  # pusha o nowym zleceniu (rola obserwatora — nie zapisuje się na zlecenia,
  # więc i ping byłby spamem). Feed / turbo broadcasty lecą real-time dla
  # wszystkich — opóźnienie dotyczy tylko web-pushy.
  NEW_EVENT_LAGGING_TITLES  = %w[kurzy_pacholek].freeze
  NEW_EVENT_EXCLUDED_TITLES = %w[zoltodziob].freeze
  NEW_EVENT_LAGGING_DELAY   = 5.minutes

  belongs_to :host
  belongs_to :creator, class_name: "User", optional: true
  belongs_to :event_campaign, optional: true
  has_many :participations, dependent: :destroy
  has_many :users, through: :participations
  has_many :carpool_offers, dependent: :destroy
  has_many :carpool_requests, through: :carpool_offers
  has_many :changes_log, class_name: "EventChange", dependent: :destroy
  has_many :swap_proposals, dependent: :destroy

  # Ustawiane przez kontroler tuż przed zapisem — żeby `log_changes` umiał wpisać
  # autora edycji do EventChange.user_id. Na nowych eventach zostawiamy nil.
  attr_accessor :edited_by

  # Zapis od razu: virtual attribute set from the event-creation form. Handled
  # in-transaction (after_create, NOT after_create_commit) so the confirmed
  # participations exist before `seed_reservations` fires — `invite_candidates`
  # then naturally excludes them, which enforces "mistrz dodany od razu = brak
  # osobnej rezerwacji dla niego". Działa też na update — admin może dorzucić
  # ludzi do istniejącego eventu (np. po bumpie capacity 3→6).
  attr_accessor :pre_registered_user_ids

  after_create         :process_pre_registrations
  after_update         :process_pre_registrations
  after_create_commit  :broadcast_feed_append,        if: :feed_visible_now?
  after_create_commit  :broadcast_visit_to_feed,      if: :feed_visible_now?
  after_create_commit  :notify_new_event_subscribers, if: :upcoming_now?
  after_create_commit  :seed_reservations,            if: :upcoming_now?
  after_create_commit  :revive_completed_campaign,    if: :upcoming_sub_event?
  after_create_commit  :seed_from_campaign_roster,    if: :upcoming_sub_event?
  after_create_commit  :notify_sub_event_added,       if: :upcoming_sub_event?
  after_create_commit  :schedule_reminder,            if: :upcoming_now?
  # Wszystko, co czyta `saved_changes`, musi lecieć PRZED
  # `refill_on_capacity_increase` — ten woła `ReservationService.fill_open_slots`
  # → `event.lock!` → `reload`, co czyści saved_changes.
  after_update_commit  :log_changes
  after_update_commit  :broadcast_feed_replace
  after_update_commit  :notify_users_of_changes
  # Uwaga: celowo alias, nie ta sama nazwa — Rails deduplikuje after_commit po
  # nazwie metody, więc drugi `:schedule_reminder` nadpisałby rejestrację z create.
  after_update_commit  :reschedule_reminder, if: -> { saved_change_to_scheduled_at? && upcoming_now? }
  after_update_commit  :refill_on_capacity_increase
  after_update_commit  :demote_on_capacity_decrease
  after_destroy_commit :broadcast_feed_remove

  # Strip nazwy — inaczej „2 auta " (trailing space z API create, które nie
  # przycinało params[:name]) vs. „2 auta" z edycji renderowałoby się w historii
  # jako fałszywa zmiana „2 auta → 2 auta" (i wysyłało push :event_changed).
  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true
  validates :scheduled_at, :ends_at, presence: true
  validates :pay_per_person, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :capacity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate  :ends_at_after_scheduled_at

  scope :upcoming, -> { where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :awaiting_completion, -> { where("ends_at < ? AND completed_at IS NULL", Time.current) }
  # „Wykonane" w UI: wszystko od momentu startu — w trakcie (started, brak completed_at)
  # i już zakończone. EventCompletionJob nie odpala się natychmiast po ends_at, więc
  # filtrowanie tylko po `completed_at` zostawiało dziurę: event w trakcie nie był
  # ani w upcoming, ani w „Wykonane".
  scope :past, -> { where("scheduled_at <= ?", Time.current).order(scheduled_at: :desc) }

  def to_param
    slug = name.to_s.parameterize
    slug.present? ? "#{id}-#{slug}" : id.to_s
  end

  def completed?
    completed_at.present?
  end

  # Event jest „zablokowany" od momentu startu — żadnych zmian w roster, kierowcach,
  # pasażerach, czacie. Predykat działa też dla eventów już zakończonych
  # (`completed?`), więc lock obowiązuje od scheduled_at na zawsze.
  def started?
    scheduled_at.present? && scheduled_at <= Time.current
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
      all_parts = participations.includes(user: { photo_attachment: :blob }).order(:position).to_a

      by_status = all_parts.group_by(&:status)

      offers   = carpool_offers.includes(carpool_requests: :user).to_a
      offers_by_user = offers.index_by(&:user_id)
      # user_id → CarpoolRequest (theirs as a passenger on this event, if any)
      own_requests = {}
      offers.each do |o|
        o.carpool_requests.each { |r| own_requests[r.user_id] = r }
      end

      pending_swaps = swap_proposals.pending.where("expires_at > ?", Time.current).to_a

      {
        reserved:               by_status["reserved"]  || [],
        confirmed:              by_status["confirmed"] || [],
        waitlist:               by_status["waitlist"]  || [],
        participations_by_user: all_parts.index_by(&:user_id),
        carpool_offers:         offers,
        carpool_offers_by_user: offers_by_user,
        carpool_request_by_user: own_requests,
        swap_proposals_by_target:   pending_swaps.group_by(&:target_id),
        swap_proposals_by_proposer: pending_swaps.group_by(&:proposer_id)
      }
    end
  end

  # True if the given user currently holds an active participation (confirmed
  # / reserved / waitlist) on this event — used to gate carpool UI actions.
  def participant?(user)
    return false if user.blank?
    participations.where(user_id: user.id, status: %i[confirmed reserved waitlist]).exists?
  end

  # Liczba pozycji jakie pojawią się na stronie historii. Musi być spójna
  # z `EventsController#build_history_entries`: 1 wpis „utworzono" + jeden wpis
  # per ParticipationEvent (audit log) + zmiany pól z `changes_log`.
  def history_count
    1 + ParticipationEvent.joins(:participation).where(participations: { event_id: id }).count + changes_count
  end

  private

  def ends_at_after_scheduled_at
    return if ends_at.blank? || scheduled_at.blank?
    errors.add(:ends_at, :must_be_after_start) if ends_at <= scheduled_at
  end

  def upcoming_now?
    scheduled_at.present? && scheduled_at > Time.current
  end

  def upcoming_sub_event?
    upcoming_now? && event_campaign_id.present?
  end

  # Sub-eventy NIE pojawiają się w feedzie `/eventy` (filtrowane po
  # `event_campaign_id: nil`) — więc nie powinny też wysyłać `:append`,
  # `:visit` ani `:remove` na `:events` stream. Inaczej `broadcast_visit_to_feed`
  # przy tworzeniu serii z N sub-eventami przerzucał twórcę na ostatni
  # sub-event zamiast zostawić go na stronie serii.
  def feed_visible_now?
    upcoming_now? && event_campaign_id.nil?
  end

  # Dorzucenie przyszłego zlecenia do zakończonej serii przywraca kampanię
  # do aktywnych — scope `EventCampaign.active` wymaga `completed_at: nil`,
  # więc bez tego nowy termin byłby niewidoczny w feedzie. EventCompletionJob
  # oznaczy kampanię ponownie jako ukończoną, gdy wszystkie sub-eventy się odbędą.
  def revive_completed_campaign
    event_campaign.update!(completed_at: nil) if event_campaign.completed?
  end

  def seed_from_campaign_roster
    CampaignSubEventSeeder.call(self)
  end

  def notify_sub_event_added
    WebPushNotifier.perform_later(:sub_event_added, event_id: id)
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
    return if event_campaign_id.present?
    return unless saved_changes.keys.intersect?(FEED_CARD_FIELDS)

    broadcast_replace_to(
      :events,
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "events/event_card",
      locals: { event: self }
    )
  end

  def broadcast_feed_remove
    return if event_campaign_id.present?
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
    return if event_campaign_id.present?

    immediate_titles = User.titles.keys - NEW_EVENT_LAGGING_TITLES - NEW_EVENT_EXCLUDED_TITLES
    WebPushNotifier.perform_later(:new_event, event_id: id, titles: immediate_titles)
    WebPushNotifier.set(wait: NEW_EVENT_LAGGING_DELAY)
                   .perform_later(:new_event, event_id: id, titles: NEW_EVENT_LAGGING_TITLES)
  end

  def seed_reservations
    return if event_campaign_id?
    ReservationService.seed_on_create(self)
  end

  # Przypomnienie push godzinę przed startem — dla flat eventów i sub-eventów
  # serii tak samo (odbiorcy = confirmed z rosteru TEGO eventu). Wołany też
  # przy każdej zmianie scheduled_at: nowy job idzie na nowy termin, a stary
  # unieważnia się sam w EventReminderJob. Samo porównanie `scheduled_for` nie
  # wystarcza: przełożenie eventu i powrót do pierwotnej godziny (A→B→A) daje
  # dwa joby z identycznym `scheduled_for` i podwójny push (tak 13.07.2026
  # zdublowało się przypomnienie o „1 auto") — stąd `reminder_generation`:
  # każdy schedule bumpuje licznik, ważny jest tylko job z aktualną generacją.
  # Event utworzony/przełożony na mniej niż godzinę przed startem — bez
  # przypomnienia („za godzinę" byłoby już nieprawdą).
  def schedule_reminder
    remind_at = scheduled_at - EventReminderJob::LEAD_TIME
    return unless remind_at.future?

    update_column(:reminder_generation, reminder_generation + 1)
    EventReminderJob.set(wait_until: remind_at)
                    .perform_later(event_id: id, scheduled_for: scheduled_at,
                                   generation: reminder_generation)
  end
  alias_method :reschedule_reminder, :schedule_reminder

  # Zapisuje wpis do `event_changes` per zmienione pole z TRACKED_FIELDS.
  # `edited_by` ustawia kontroler — gdy nil (callback z konsoli, jobów itd.),
  # log idzie z user_id = nil.
  def log_changes
    significant_changed_fields.each do |field|
      prev_v, new_v = saved_changes[field]
      changes_log.create!(
        user:           edited_by,
        field:          field,
        previous_value: prev_v.to_s,
        new_value:      new_v.to_s
      )
    end
  end

  # Push :event_changed idzie do WSZYSTKICH userów z subskrypcjami (decyzja
  # produktowa — nie tylko do uczestników), stąd nazwa bez „participants".
  def notify_users_of_changes
    return if started?

    changed_fields = significant_changed_fields
    return if changed_fields.empty?

    WebPushNotifier.perform_later(:event_changed, event_id: id, changed_fields: changed_fields)
  end

  # Pola z TRACKED_FIELDS, które faktycznie się zmieniły — z pominięciem różnic
  # kosmetycznych w białych znakach (np. „2 auta " → „2 auta"), które w historii
  # renderowałyby się jako identyczne „przed → po". Wspólne dla logu i pusha,
  # żeby oba widziały tę samą listę zmian.
  def significant_changed_fields
    EventChange::TRACKED_FIELDS.select do |field|
      next false unless saved_changes.key?(field)
      prev_v, new_v = saved_changes[field]
      prev_v.to_s.strip != new_v.to_s.strip
    end
  end

  def process_pre_registrations
    ids = Array(pre_registered_user_ids).map(&:to_i).uniq.reject(&:zero?)
    return if ids.empty?

    blocked = HostBlock.where(host_id: host_id).pluck(:user_id).to_set
    # Mistrz Pióra zawsze idzie przez flow zaproszenia (rezerwacja + accept/decline),
    # nawet jeśli ktoś zaznaczy go w „Zapisz od razu". Po pominięciu ich tutaj
    # `seed_reservations` (after_create_commit) złapie ich jako kandydatów do
    # invite_candidates i wyśle zaproszenie.
    mistrz_ids = User.mistrz_piora.where(id: ids).pluck(:id).to_set
    # Pomijamy istniejących uczestników (active + cancelled) — uniqueness
    # (event_id, user_id) i tak by uderzyła. Re-aktywacja anulowanego musi
    # iść normalnym torem (controller / konsola).
    existing_ids = participations.where(user_id: ids).pluck(:user_id).to_set
    ordered = ids.reject { |i| blocked.include?(i) || mistrz_ids.include?(i) || existing_ids.include?(i) }
    return if ordered.empty?

    users = User.where(id: ordered).index_by(&:id)
    open_slots = [ capacity - participations.holding_slot.count, 0 ].max
    confirmed_ids, waitlist_ids = ordered.first(open_slots), ordered.drop(open_slots)

    next_confirmed_pos = (participations.confirmed.maximum(:position) || 0) + 1
    next_waitlist_pos  = (participations.waitlist.maximum(:position)  || 0) + 1

    confirmed_ids.each_with_index do |uid, idx|
      next unless users[uid]
      participations.create!(user: users[uid], status: :confirmed, position: next_confirmed_pos + idx)
    end
    waitlist_ids.each_with_index do |uid, idx|
      next unless users[uid]
      participations.create!(user: users[uid], status: :waitlist, position: next_waitlist_pos + idx)
    end
  end

  # Host bumped capacity → promote from waitlist (or invite top-tier) to fill
  # the freshly-opened slots. No-op on decrease (handled by
  # `demote_on_capacity_decrease`) or on updates that don't touch capacity.
  def refill_on_capacity_increase
    return unless saved_change_to_capacity?
    old_cap, new_cap = saved_change_to_capacity
    return unless new_cap.to_i > old_cap.to_i
    ReservationService.fill_open_slots(self)
  end

  # Host shrunk capacity below the confirmed headcount → push the most-recently
  # confirmed users back onto the waitlist (front of the queue). No-op when
  # confirmed_count still fits inside the new capacity, or on capacity bumps.
  def demote_on_capacity_decrease
    return unless saved_change_to_capacity?
    old_cap, new_cap = saved_change_to_capacity
    return unless new_cap.to_i < old_cap.to_i
    ReservationService.demote_overflow(self)
  end
end
