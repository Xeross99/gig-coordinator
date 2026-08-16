class EventsController < ApplicationController
  before_action :require_user!
  before_action :require_event_creator!, only: %i[new create]
  before_action :require_event_manager!, only: %i[edit update destroy]

  FILTERS = %w[new completed].freeze

  def index
    @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "new"
    events = if @filter == "completed"
      past = Event.past.includes(host: { photo_attachment: :blob })
      past.where(event_campaign_id: nil)
          .or(past.where.not(event_campaign_id: EventCampaign.completed.select(:id)))
    else
      Event.upcoming.where(event_campaign_id: nil)
        .includes(host: { photo_attachment: :blob })
    end.to_a
    @pending_event_ids = Set.new(
      Current.user.participations.reserved
        .where("reserved_until > ?", Time.current)
        .pluck(:event_id)
    )
    @my_status_by_event_id = Current.user.participations
                                    .where(event_id: events.map(&:id))
                                    .where.not(status: :cancelled)
                                    .index_by(&:event_id)
                                    .transform_values(&:status)
    campaigns_scope = @filter == "completed" ? EventCampaign.completed : EventCampaign.active
    campaigns = campaigns_scope.includes(host: { photo_attachment: :blob }).to_a
    @pending_campaign_ids = Set.new(
      CampaignParticipation.where(user_id: Current.user.id, status: :reserved)
                           .where("reserved_until > ?", Time.current)
                           .pluck(:event_campaign_id)
    )

    # Dane dla kart kampanii zbatchowane tutaj (3 zapytania na cały feed) —
    # partial ma fallback na własne zapytania dla broadcastów, ale bez tych
    # locals feed robił ~4 zapytania na każdą kampanię.
    campaign_ids = campaigns.map(&:id)
    @campaign_upcoming_events = Event.where(event_campaign_id: campaign_ids)
                                     .where("scheduled_at > ?", Time.current)
                                     .order(:scheduled_at)
                                     .group_by(&:event_campaign_id)
    @campaign_slots_taken = CampaignParticipation.holding_slot
                                                 .where(event_campaign_id: campaign_ids)
                                                 .group(:event_campaign_id).count
    preview_ids = @campaign_upcoming_events.values.flatten.map(&:id)
    @my_sub_event_statuses = Current.user.participations
                                    .where(event_id: preview_ids)
                                    .where.not(status: :cancelled)
                                    .index_by(&:event_id)
                                    .transform_values(&:status)

    # Wspólny feed kampanii + flat eventów posortowany chronologicznie po
    # `scheduled_at` (dla kampanii: najbliższy nadchodzący sub-event w „new",
    # ostatni miniony w „completed"). Sortowanie wyłącznie na poziomie wiersza,
    # broadcasty (`broadcast_prepend_to`) wciąż lecą na top listy — świeża
    # kreacja prawie nigdy nie jest najwcześniejsza w czasie, więc prepend bywa
    # nie-na-miejscu, ale po refreshu wraca chronologia.
    @feed = build_feed(events, campaigns)
  end

  def show
    @event = Event.includes(:host).find(params[:id])
    @host  = @event.host
  end

  def history
    @event = Event.includes(:host, :creator).find(params[:id])
    @entries = build_history_entries(@event)
  end

  # GET /eventy/:id/kalendarz
  # Zwraca standardowy plik iCalendar (RFC 5545) — iOS/macOS Calendar.app,
  # Google Calendar i Outlook honorują `text/calendar` i otwierają preview
  # „Dodaj do kalendarza". Jeden link → wszystkie platformy. UID jest
  # deterministyczny (`event-#{id}@host`), żeby ponowny import zaktualizował
  # istniejący wpis zamiast duplikować. Brak gatingu po participation —
  # link jest renderowany tylko dla confirmed/reserved w `_participation_button`,
  # a sam endpoint zostawiamy dostępny dla każdego zalogowanego (taki sam
  # próg jak event show, do którego user już ma dostęp).
  def calendar
    event = Event.includes(:host).find(params[:id])
    send_data EventIcsBuilder.build([ event ], calendar_name: "Gig Coordinator — #{event.name}"),
              type: "text/calendar; charset=UTF-8",
              disposition: %(inline; filename="event-#{event.id}.ics"),
              filename: nil
  end

  def new
    @event = Event.new(scheduled_at: 1.day.from_now.change(hour: 18, min: 0), capacity: 4)
    @hosts = allowed_hosts.order(:last_name, :first_name)
    @users_for_prereg = users_for_prereg(@event)
  end

  def create
    @event = Event.new(event_params)
    @event.creator = Current.user
    unless allowed_hosts.exists?(id: @event.host_id)
      redirect_to events_path, alert: "Nie masz uprawnień do planowania zleceń." and return
    end
    if @event.save
      redirect_to event_path(@event), notice: "Zlecenie dodane. Zaproszenia już poszły."
    else
      @hosts = allowed_hosts.order(:last_name, :first_name)
      @users_for_prereg = users_for_prereg(@event)
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @hosts = allowed_hosts.order(:last_name, :first_name)
    @users_for_prereg = users_for_prereg(@event)
  end

  def update
    @event.edited_by = Current.user
    if @event.update(event_params)
      redirect_to event_path(@event), notice: "Zmiany zapisane."
    else
      @hosts = allowed_hosts.order(:last_name, :first_name)
      @users_for_prereg = users_for_prereg(@event)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @event.destroy
    redirect_to events_path, notice: "Zlecenie usunięte."
  end

  private

  # Klucz sortowania dla kampanii w feedzie: w trybie „new" — najbliższy
  # nadchodzący sub-event, w „completed" — ostatni miniony. Brak sub-eventów →
  # kampania ląduje na końcu listy (sentinel daleko w przyszłość/przeszłość).
  def build_feed(events, campaigns)
    ascending = @filter != "completed"
    campaign_keys = campaign_sort_keys(campaigns, ascending)
    fallback = ascending ? Time.current + 100.years : Time.current - 100.years

    rows = events.map { |e| { kind: :event, item: e, sort_key: e.scheduled_at } } +
           campaigns.map { |c| { kind: :campaign, item: c, sort_key: campaign_keys[c.id] || fallback } }

    rows.sort_by! { |r| r[:sort_key] }
    rows.reverse! unless ascending
    rows
  end

  def campaign_sort_keys(campaigns, ascending)
    ids = campaigns.map(&:id)
    return {} if ids.empty?
    scope = Event.where(event_campaign_id: ids)
    if ascending
      scope.where("scheduled_at > ?", Time.current).group(:event_campaign_id).minimum(:scheduled_at)
    else
      scope.where("scheduled_at <= ?", Time.current).group(:event_campaign_id).maximum(:scheduled_at)
    end
  end

  def build_history_entries(event)
    entries = [ { at: event.created_at, kind: :created, creator: event.creator, host: event.host } ]

    # ParticipationEvent (audit log) jest źródłem prawdy o tym co się stało
    # z każdym uczestnikiem — pokazuje zaproszenia (reserved), przyjęcia
    # (accepted), odrzucenia (declined), promocje z waitlisty (promoted) i
    # wygaśnięcia rezerwacji (expired). Wcześniej historia inferowała stan
    # tylko z `created_at`/`updated_at` Participation i finalnego statusu,
    # przez co np. „odrzucił zaproszenie" wyglądał jak „anulował udział".
    event.participations.includes(:participation_events, user: { photo_attachment: :blob }).each do |p|
      p.participation_events.each do |pe|
        entries << { at: pe.created_at, kind: :participation_event, participation: p, participation_event: pe }
      end
    end

    event.changes_log.includes(:user).each do |c|
      entries << { at: c.created_at, kind: :edited, change: c }
    end
    entries.sort_by { |e| e[:at] }.reverse
  end

  def allowed_hosts
    Current.user.allowed_hosts
  end

  def users_for_prereg(event)
    User.available_for_prereg(
      excluding: (event.participations.select(:user_id) if event&.persisted?)
    )
  end

  def require_event_creator!
    return if Current.user&.can_create_events?

    redirect_to root_path, alert: "Nie masz uprawnień do planowania zleceń."
  end

  def require_event_manager!
    @event = Event.find(params[:id])
    return if Current.user&.can_manage_event?(@event)

    redirect_to event_path(@event), alert: "Nie masz uprawnień do zarządzania tym zleceniem."
  end

  def event_params
    raw = params.require(:event).permit(:name, :host_id, :event_date,
                                        :start_hour, :start_minute,
                                        :duration_hours, :duration_minutes,
                                        :pay_per_person, :capacity, :notes,
                                        pre_registered_user_ids: [])
    EventSchedule.compose(raw)
  end
end
