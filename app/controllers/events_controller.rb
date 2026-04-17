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

  def require_master!
    return if current_user&.master?
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
