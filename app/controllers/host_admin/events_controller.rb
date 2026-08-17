module HostAdmin
  class EventsController < BaseController
    before_action :set_event, only: %i[show edit update destroy]

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
        redirect_to host_event_path(@event), notice: "Nowe zlecenie"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      # A host is editing, not a worker - the change log row gets user_id = nil,
      # which the history renders as „przez gospodarza".
      @event.edited_by = nil

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

    def set_event
      @event = Current.host.events.find(params[:id])
    end

    def event_params
      raw = params.require(:event).permit(:name, :event_date,
                                          :start_hour, :start_minute,
                                          :duration_hours, :duration_minutes,
                                          :pay_per_person, :capacity)
      EventSchedule.compose(raw)
    end
  end
end
