# Składa `scheduled_at`/`ends_at` z surowych pól formularza/API:
# `event_date` + `start_hour`/`start_minute` (dwa selecty 24h) oraz
# `duration_hours`/`duration_minutes`. Model trzyma dwa pełne datetime'y —
# rozbicie na osobne pola jest wyłącznie UI-owe, a to jest jedyne miejsce,
# gdzie te pola są sklejane z powrotem (web, panel hosta, kampanie, API).
#
# `attrs` może być ActionController::Parameters (permitted), Hash lub
# HashWithIndifferentAccess — surowe pola są z niego USUWANE (delete),
# a przy kompletnych danych dopisywane są `scheduled_at`/`ends_at`.
# Guard: bez `event_date` + `start_hour` nic nie składamy (zachowanie
# webowe — API wcześniej parsowało "na ślepo" i przy braku daty
# produkowało dzisiejszą północ; teraz brak danych = brak zmiany pól).
module EventSchedule
  def self.compose(attrs)
    date         = attrs.delete(:event_date)
    start_hour   = attrs.delete(:start_hour)
    start_minute = attrs.delete(:start_minute)
    hours        = attrs.delete(:duration_hours).to_i
    minutes      = attrs.delete(:duration_minutes).to_i

    if date.present? && start_hour.present?
      time_str  = format("%02d:%02d", start_hour.to_i, start_minute.to_i)
      scheduled = Time.zone.parse("#{date} #{time_str}")
      attrs[:scheduled_at] = scheduled
      attrs[:ends_at]      = scheduled + hours.hours + minutes.minutes
    end

    attrs
  end
end
