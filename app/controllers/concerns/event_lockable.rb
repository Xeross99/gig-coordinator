module EventLockable
  extend ActiveSupport::Concern

  included do
    before_action :set_event
    before_action :enforce_event_lock!
  end

  private

  def set_event
    @event = Event.find(params[:event_id])
  end

  def enforce_event_lock!
    return unless @event.started?

    redirect_to event_path(@event), alert: "Zlecenie już się rozpoczęło - zmiany niemożliwe."
  end
end
