# Render rostra jest kosztowny — default + wersje spersonalizowane per user
# z rolą (kierowcy/pasażerowie/waitlisterzy). Broadcast leci więc z kolejki,
# żeby request, który zmienił uczestnictwo, nie płacił za renderowanie.
# Idempotentny: event mógł zniknąć zanim job ruszył (dependent: :destroy).
class EventRosterBroadcastJob < ApplicationJob
  queue_as :default

  def perform(event_id:, counts: false)
    event = Event.find_by(id: event_id)
    return unless event

    EventRosterBroadcaster.broadcast(event)
    return unless counts

    Turbo::StreamsChannel.broadcast_replace_to(
      [ event, :counts ],
      target: ActionView::RecordIdentifier.dom_id(event, :counts),
      partial: "events/counts",
      locals: { event: event }
    )
  end
end
