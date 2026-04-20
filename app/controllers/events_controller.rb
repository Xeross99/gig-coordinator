class EventsController < ApplicationController
  before_action :require_user!
  before_action :require_master!, only: %i[new create]

  def index
    @events = Event.upcoming.includes(:host)
    @events = @events.where(host_id: params[:host_id]) if params[:host_id].present?
    @hosts = Host.order(:last_name, :first_name)
    @selected_host_id = params[:host_id].presence&.to_i
  end

  def show
    @event = Event.includes(:host).find(params[:id])
    @host  = @event.host
  end

  # Chronological timeline of what happened on this event — creation + every
  # participation row (join, status change, cancel). We don't keep a dedicated
  # audit log, so we lean on participations.created_at (original join) plus
  # updated_at (last status change) as two separate timeline points.
  def history
    @event = Event.includes(:host).find(params[:id])
    @entries = build_history_entries(@event)
  end

  def new
    @event = Event.new(scheduled_at: 1.day.from_now.change(hour: 18, min: 0), capacity: 4)
    @hosts = Host.order(:last_name, :first_name)
  end

  def create
    @event = Event.new(event_params)
    if @event.save
      redirect_to event_path(@event), notice: I18n.t("events.created")
    else
      @hosts = Host.order(:last_name, :first_name)
      render :new, status: :unprocessable_content
    end
  end

  private

  # Pair of timeline entries per participation: one for the initial join
  # (created_at) and, if the row was touched later, one for the latest status
  # change (updated_at). Plus a single entry for when the event was created.
  def build_history_entries(event)
    entries = [ { at: event.created_at, kind: :created, host: event.host } ]
    event.participations.includes(user: { photo_attachment: :blob }).each do |p|
      entries << { at: p.created_at, kind: :joined, participation: p }
      if p.updated_at > p.created_at + 1.second
        entries << { at: p.updated_at, kind: :status_change, participation: p }
      end
    end
    # Newest first — reads like a feed: the latest action on top, event
    # creation at the bottom.
    entries.sort_by { |e| e[:at] }.reverse
  end

  def require_master!
    return if Current.user&.master?

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
