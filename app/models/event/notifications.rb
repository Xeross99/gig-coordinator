module Event::Notifications
  extend ActiveSupport::Concern

  # Web push fired by the event itself: „nowe zlecenie", „zmieniono szczegóły"
  # and the reminder an hour before the start. Pushes tied to the roster
  # (promotion, invitation…) live on Participation / ReservationService.

  # Pachołkowie (praktykanci) dostają push o nowym zleceniu 5 min po wyższych
  # rangach — wyższe mają wtedy fory na zapis. Żółtodziób w ogóle nie dostaje
  # pusha o nowym zleceniu (rola obserwatora — nie zapisuje się na zlecenia,
  # więc i ping byłby spamem). Feed / turbo broadcasty lecą real-time dla
  # wszystkich — opóźnienie dotyczy tylko web-pushy.
  NEW_EVENT_LAGGING_TITLES  = %w[kurzy_pacholek].freeze
  NEW_EVENT_EXCLUDED_TITLES = %w[zoltodziob].freeze
  NEW_EVENT_LAGGING_DELAY   = 5.minutes

  included do
    after_create_commit :notify_new_event_subscribers, if: :upcoming_now?
    after_create_commit :schedule_reminder,            if: :upcoming_now?
    after_update_commit :notify_users_of_changes
    # Uwaga: celowo alias, nie ta sama nazwa — Rails deduplikuje after_commit po
    # nazwie metody, więc drugi `:schedule_reminder` nadpisałby rejestrację z create.
    after_update_commit :reschedule_reminder, if: -> { saved_change_to_scheduled_at? && upcoming_now? }
  end

  private

  def notify_new_event_subscribers
    return if event_campaign_id.present?

    immediate_titles = User.titles.keys - NEW_EVENT_LAGGING_TITLES - NEW_EVENT_EXCLUDED_TITLES
    WebPushNotifier.perform_later(:new_event, event_id: id, titles: immediate_titles)
    WebPushNotifier.set(wait: NEW_EVENT_LAGGING_DELAY)
                   .perform_later(:new_event, event_id: id, titles: NEW_EVENT_LAGGING_TITLES)
  end

  # Push :event_changed idzie do WSZYSTKICH userów z subskrypcjami (decyzja
  # produktowa — nie tylko do uczestników), stąd nazwa bez „participants".
  # `significant_changed_fields` mieszka w Event::ChangeLog — log i push muszą
  # widzieć tę samą listę zmian.
  def notify_users_of_changes
    return if started?

    changed_fields = significant_changed_fields
    return if changed_fields.empty?

    WebPushNotifier.perform_later(:event_changed, event_id: id, changed_fields: changed_fields)
  end

  # Przypomnienie push godzinę przed startem — dla flat eventów i sub-eventów
  # serii tak samo (odbiorcy = confirmed z rosteru TEGO eventu). Wołany też
  # przy każdej zmianie scheduled_at: nowy job idzie na nowy termin, a stary
  # unieważnia się sam w EventReminderJob. Samo porównanie `scheduled_for` nie
  # wystarcza: przełożenie eventu i powrót do pierwotnej godziny (A→B→A) daje
  # dwa joby z identycznym `scheduled_for` i podwójny push (tak 13.07.2026
  # zdublowało się przypomnienie o „1 auto") — stąd `reminder_generation`:
  # każdy schedule bumpuje licznik, ważny jest tylko job z aktualną generacją.
  # Event utworzony/przełożony na mniej niż godzinę przed startem — bez
  # przypomnienia („za godzinę" byłoby już nieprawdą).
  def schedule_reminder
    remind_at = scheduled_at - EventReminderJob::LEAD_TIME
    return unless remind_at.future?

    update_column(:reminder_generation, reminder_generation + 1)
    EventReminderJob.set(wait_until: remind_at)
                    .perform_later(event_id: id, scheduled_for: scheduled_at,
                                   generation: reminder_generation)
  end
  alias_method :reschedule_reminder, :schedule_reminder
end
