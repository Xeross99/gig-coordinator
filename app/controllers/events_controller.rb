class EventsController < ApplicationController
  before_action :require_user!
  before_action :require_event_creator!, only: %i[new create]

  FILTERS = %w[new completed].freeze

  def index
    @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "new"
    @events = (@filter == "completed" ? Event.completed : Event.upcoming)
      .includes(host: { photo_attachment: :blob })
  end

  def show
    @event = Event.includes(:host).find(params[:id])
    @host  = @event.host
  end

  def history
    @event = Event.includes(:host).find(params[:id])
    @entries = build_history_entries(@event)
  end

  def new
    @event = Event.new(scheduled_at: 1.day.from_now.change(hour: 18, min: 0), capacity: 4)
    @hosts = allowed_hosts.order(:last_name, :first_name)
  end

  def create
    @event = Event.new(event_params)
    unless Current.user.can_submit_events?
      redirect_to events_path, alert: I18n.t("events.submit_disabled_hint") and return
    end
    unless allowed_hosts.exists?(id: @event.host_id)
      redirect_to events_path, alert: I18n.t("events.new_event_forbidden") and return
    end
    if @event.save
      redirect_to event_path(@event), notice: I18n.t("events.created")
    else
      @hosts = allowed_hosts.order(:last_name, :first_name)
      render :new, status: :unprocessable_content
    end
  end

  private

  def build_history_entries(event)
    entries = [ { at: event.created_at, kind: :created, host: event.host } ]
    event.participations.includes(user: { photo_attachment: :blob }).each do |p|
      entries << { at: p.created_at, kind: :joined, participation: p }
      if p.updated_at > p.created_at + 1.second
        entries << { at: p.updated_at, kind: :status_change, participation: p }
      end
    end
    entries.sort_by { |e| e[:at] }.reverse
  end

  def allowed_hosts
    return Host.all                   if Current.user.master?
    return Current.user.managed_hosts if Current.user.captain?
    Host.none
  end

  def require_event_creator!
    return if Current.user&.can_create_events?

    redirect_to root_path, alert: I18n.t("events.new_event_forbidden")
  end

  def event_params
    raw = params.require(:event).permit(:name, :host_id, :event_date,
                                        :start_hour, :start_minute,
                                        :duration_hours, :duration_minutes,
                                        :pay_per_person, :capacity)

    date         = raw.delete(:event_date)
    start_hour   = raw.delete(:start_hour)
    start_minute = raw.delete(:start_minute)
    hours        = raw.delete(:duration_hours).to_i
    minutes      = raw.delete(:duration_minutes).to_i

    if date.present? && start_hour.present?
      time_str  = format("%02d:%02d", start_hour.to_i, start_minute.to_i)
      scheduled = Time.zone.parse("#{date} #{time_str}")
      raw[:scheduled_at] = scheduled
      raw[:ends_at]      = scheduled + hours.hours + minutes.minutes
    end

    raw
  end
end
