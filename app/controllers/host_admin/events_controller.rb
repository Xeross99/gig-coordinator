module HostAdmin
  class EventsController < BaseController
    before_action :load_event, only: %i[show edit update destroy]

    def index
      @events = current_host.events.order(scheduled_at: :desc)
    end

    def show; end

    def new
      @event = current_host.events.new(scheduled_at: 1.day.from_now, ends_at: 1.day.from_now + 2.hours, capacity: 4)
    end

    def create
      @event = current_host.events.new(event_params)
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
      @event = current_host.events.find(params[:id])
    end

    def event_params
      params.expect(event: %i[name scheduled_at ends_at pay_per_person capacity])
    end
  end
end
