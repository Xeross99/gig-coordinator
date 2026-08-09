class EventReminderJob < ApplicationJob
  queue_as :default

  LEAD_TIME = 1.hour

  # Per-event przypomnienie godzinę przed startem: schedulowany przy tworzeniu
  # eventu (i przy każdej zmianie scheduled_at) z `wait_until: scheduled_at -
  # LEAD_TIME` — zamiast recurring sweepera. Idempotentny: `scheduled_for` to
  # termin eventu z momentu schedulowania. Jeśli event został w międzyczasie
  # przełożony, callback modelu wysłał już świeży job na nowy termin, a ten
  # stary rozpoznaje przełożenie po niezgodności terminów i nic nie robi.
  # `generation` domyka lukę A→B→A: po przełożeniu i powrocie do pierwotnej
  # godziny dwa joby mają ten sam `scheduled_for`, ale tylko najnowszy ma
  # aktualne `Event#reminder_generation` — starszy no-opuje zamiast dublować
  # push. `generation: nil` = job zserializowany przed wprowadzeniem licznika
  # (wciąż w kolejce po deployu) — dla niego zostaje samo porównanie terminów.
  # Eventy usunięte / już rozpoczęte też są pomijane.
  def perform(event_id:, scheduled_for:, generation: nil)
    event = Event.find_by(id: event_id)
    return unless event
    return if event.scheduled_at.to_i != scheduled_for.to_i
    return if generation && event.reminder_generation != generation
    return if event.started?

    WebPushNotifier.perform_later(:event_reminder, event_id: event.id)
  end
end
