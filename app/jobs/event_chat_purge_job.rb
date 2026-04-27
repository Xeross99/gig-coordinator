class EventChatPurgeJob < ApplicationJob
  queue_as :default

  # Idempotentny: enqueue'owany przez Event#schedule_chat_purge na scheduled_at
  # i ponownie przez sweep job. Jeśli scheduled_at zostało odsunięte w przyszłość,
  # job re-enqueue'uje siebie zamiast kasować przedwcześnie.
  def perform(event_id)
    event = Event.find_by(id: event_id) or return

    if event.started?
      purge!(event)
    elsif event.scheduled_at.present?
      EventChatPurgeJob.set(wait_until: event.scheduled_at).perform_later(event.id)
    end
  end

  private

  def purge!(event)
    return unless event.messages.exists?
    event.messages.delete_all
    Turbo::StreamsChannel.broadcast_replace_to(
      event, :chat,
      target: "event_chat",
      partial: "chats/locked",
      locals: { event: event }
    )
  end
end
