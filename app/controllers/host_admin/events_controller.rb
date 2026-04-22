module HostAdmin
  class EventsController < BaseController
    before_action :load_event, only: %i[show edit update destroy]

    def index
      @events = Current.host.events.order(scheduled_at: :desc)
    end

    def show
      @history = ParticipationEvent
        .joins(:participation)
        .where(participations: { event_id: @event.id })
        .includes(participation: { user: { photo_attachment: :blob } })
        .order(created_at: :desc)
    end

    def new
      @event = Current.host.events.new(scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours, capacity: 4)
    end

    def create
      @event = Current.host.events.new(event_params)
      if @event.save
        redirect_to host_event_path(@event), notice: I18n.t("host_panel.new_event")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @event.update(event_params)
        redirect_to host_event_path(@event)
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @event.destroy
      redirect_to host_events_path
    end

    private

    def load_event
      @event = Current.host.events.find(params[:id])
    end

    def event_params
      raw = params.require(:event).permit(:name, :event_date,
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
end
