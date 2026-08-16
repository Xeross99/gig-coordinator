# Kontrolery mutujące zlecenie (zapisy, wymiany, podwózki) dzielą dwie rzeczy:
# ładują `@event` z zagnieżdżonego `:event_id` i odmawiają czegokolwiek po
# starcie zlecenia. Jako `before_action` filtr przerywa łańcuch sam — wcześniej
# każda akcja musiała o tym pamiętać własnym `return if enforce_event_lock!`,
# a pominięcie tej linijki w nowej akcji nie rzucałoby żadnego błędu, tylko
# cicho pozwoliłoby edytować zlecenie w trakcie.
module EventLockable
  extend ActiveSupport::Concern

  included do
    before_action :load_event
    before_action :enforce_event_lock!
  end

  private

  def load_event
    @event = Event.find(params[:event_id])
  end

  # Blokada obowiązuje od `scheduled_at` na zawsze — także po zakończeniu.
  def enforce_event_lock!
    return unless @event.started?

    redirect_to event_path(@event), alert: "Zlecenie już się rozpoczęło - zmiany niemożliwe."
  end
end
