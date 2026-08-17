module EventsHelper
  def google_maps_embed_src(location)
    "https://maps.google.com/maps?q=#{CGI.escape(location.to_s)}&output=embed"
  end

  def google_maps_open_url(location)
    "https://www.google.com/maps/search/?api=1&query=#{CGI.escape(location.to_s)}"
  end

  def event_duration_text(event)
    total_minutes = ((event.ends_at - event.scheduled_at) / 60).round
    hours, minutes = total_minutes.divmod(60)
    parts = []
    parts << "#{hours} godz." if hours.positive?
    parts << "#{minutes} min" if minutes.positive?
    parts.join(" ")
  end

  # Polish noun pluralization for "miejsce":
  #   1           → miejsce
  #   2-4 (mod10) → miejsca (except 12-14, which take "miejsc")
  #   else        → miejsc
  def seats_label(count)
    n    = count.to_i
    mod10, mod100 = n % 10, n % 100
    return "miejsce" if n == 1
    return "miejsca" if (2..4).include?(mod10) && !(12..14).include?(mod100)
    "miejsc"
  end

  # Polish pluralization for "zlecenie" — same logic as `seats_label`.
  #   1           → zlecenie
  #   2-4 (mod10) → zlecenia (except 12-14, which take "zleceń")
  #   else        → zleceń
  def jobs_label(count)
    n    = count.to_i
    mod10, mod100 = n % 10, n % 100
    return "zlecenie" if n == 1
    return "zlecenia" if (2..4).include?(mod10) && !(12..14).include?(mod100)
    "zleceń"
  end

  # Plakietka statusu uczestnictwa na kartach feedu (event card + campaign card):
  # [klasy kolorów, polska etykieta] albo nil dla statusów bez plakietki
  # (cancelled, nil). Etykiety w pl.yml pod participations.status_badge.*.
  def participation_status_badge(status)
    case status.to_s
    when "confirmed" then [ "bg-emerald-100 text-emerald-700", "Główna lista" ]
    when "waitlist"  then [ "bg-amber-100 text-amber-800",     "Rezerwa" ]
    when "reserved"  then [ "bg-indigo-100 text-indigo-700",   "Zaproszenie" ]
    end
  end

  # Compact Polish relative-time label for a given TimeWithZone — used on the
  # feed so users can tell "za 3 dni" from "3 dni temu" at a glance. Uses
  # floor/integer division everywhere to avoid weird "za 60 min" boundaries.
  def relative_time_chip(time)
    return nil if time.blank?

    diff    = (time - Time.current).to_i
    future  = diff >= 0
    abs     = diff.abs
    day_diff  = (time.to_date - Date.current).to_i
    abs_days  = day_diff.abs

    return (future ? "zaraz" : "przed chwilą") if abs < 60

    if abs < 3600
      m = abs / 60
      return future ? "za #{m} min" : "#{m} min temu"
    end

    if abs < 86_400
      h = abs / 3600
      return future ? "za #{h} godz." : "#{h} godz. temu"
    end

    return "jutro"   if day_diff ==  1
    return "wczoraj" if day_diff == -1

    if abs_days < 14
      return future ? "za #{abs_days} dni" : "#{abs_days} dni temu"
    end

    if abs_days < 30
      w = abs_days / 7
      return future ? "za #{w} tyg." : "#{w} tyg. temu"
    end

    months = abs_days / 30
    future ? "za #{months} mies." : "#{months} mies. temu"
  end

  # --- Event history timeline -------------------------------------------------

  # [bg-color-class, svg-path] pair keyed off the entry kind + participation
  # status. Icons are Heroicons mini paths (solid, 20×20 viewBox).
  # Zwraca [klasa tła kółka, nazwa ikony]. Ikona to partial z app/views/icons —
  # inline SVG, a nie plik z assetów, bo `fill="currentColor"` pozwala pomalować
  # ją klasą z zewnątrz; `image_tag` na pliku .svg tego nie potrafi.
  def history_entry_visuals(entry)
    case entry[:kind]
    when :created then [ "bg-stone-500", "plus" ]
    when :edited  then [ "bg-sky-500",   "pencil" ]
    when :participation_event
      case entry[:participation_event].event_type
      when "joined"          then [ "bg-emerald-500", "check" ]
      when "joined_waitlist" then [ "bg-orange-500",  "check" ]
      when "promoted"        then [ "bg-emerald-500", "arrow_up" ]
      when "accepted"        then [ "bg-emerald-500", "thumbs_up" ]
      when "reserved"        then [ "bg-indigo-500",  "star" ]
      when "declined"        then [ "bg-red-400",     "x_circle" ]
      when "cancelled"       then [ "bg-red-400",     "x_circle" ]
      when "expired"         then [ "bg-stone-400",   "clock" ]
      when "swapped_in"      then [ "bg-indigo-500",  "arrow_up" ]
      when "swapped_out"     then [ "bg-indigo-400",  "x_circle" ]
      else                        [ "bg-stone-400",   "clock" ]
      end
    else
      [ "bg-stone-400", "clock" ]
    end
  end

  # HTML string (safe) describing what happened. The kind controls the template,
  # participation.status fills in the verb.
  def history_entry_text(entry)
    case entry[:kind]
    when :created
      author = entry[:creator] || entry[:host]
      safe_join([ "Utworzono zlecenie przez ", tag.strong(author.display_name) ])
    when :participation_event
      safe_join([
        tag.strong(entry[:participation].user.display_name), " ",
        participation_event_verb(entry[:participation_event].event_type)
      ])
    when :edited
      render_event_change_entry(entry[:change])
    end
  end

  # Polski opis pojedynczego ParticipationEvent (audit log). Wszyscy pracownicy
  # to mężczyźni — verby tylko w formie męskiej (świadomie, nie generyczne).
  def participation_event_verb(event_type)
    case event_type
    when "joined", "joined_waitlist" then "zapisał się"
    when "cancelled"                 then "anulował udział"
    when "reserved"                  then "otrzymał zaproszenie"
    when "accepted"                  then "przyjął zaproszenie"
    when "declined"                  then "odrzucił zaproszenie"
    when "promoted"                  then "wskoczył z rezerwy"
    when "expired"                   then "rezerwacja wygasła"
    when "swapped_in"                then "wskoczył przez wymianę"
    when "swapped_out"               then "ustąpił miejsce (wymiana)"
    else                                  "zmienił status"
    end
  end

  # Wariant tej samej mapy dla historii w panelu gospodarza — inne sformułowania
  # (gospodarz patrzy na event z zewnątrz, nie na własny udział). Żył wcześniej
  # jako `t("host_panel.history.#{event_type}")` i pokrywał 7 z 10 wartości
  # enuma, więc najczęstszy typ zdarzenia (`joined_waitlist`) renderował się jako
  # „Translation missing" — i18n nie zgłasza braku klucza, tylko wstawia
  # placeholder. Tu brak trafienia spada na `else`, czyli degraduje się łagodnie.
  # Formy męskie, jak wyżej.
  def host_history_verb(event_type)
    case event_type
    when "joined"          then "zapisał się"
    when "joined_waitlist" then "zapisał się na rezerwę"
    when "cancelled"       then "zrezygnował"
    when "reserved"        then "dostał rezerwację"
    when "accepted"        then "potwierdził rezerwację"
    when "declined"        then "odrzucił rezerwację"
    when "promoted"        then "awansował z listy rezerwowej"
    when "expired"         then "rezerwacja wygasła"
    when "swapped_in"      then "wskoczył przez wymianę"
    when "swapped_out"     then "ustąpił miejsce (wymiana)"
    else                        "zmienił status"
    end
  end

  # Wpis edycji eventu — „<autor> zmienił/a <pole> z <prev> na <new>".
  # Brak autora → „Zmieniono <pole>...".
  def render_event_change_entry(change)
    label = event_change_field_label(change.field)
    prev_v = format_event_change_value(change.field, change.previous_value)
    new_v  = format_event_change_value(change.field, change.new_value)

    actor = change.user&.display_name
    prefix = if actor
      safe_join([ tag.strong(actor), " zmienił " ])
    else
      "Zmieniono ".html_safe
    end

    safe_join([
      prefix,
      tag.strong(label),
      " z ",
      tag.span(prev_v, class: "text-stone-500 line-through"),
      " na ",
      tag.strong(new_v)
    ])
  end

  def event_change_field_label(field)
    case field
    when "name"           then "nazwę"
    when "host_id"        then "gospodarza"
    when "scheduled_at"   then "datę startu"
    when "ends_at"        then "datę zakończenia"
    when "pay_per_person" then "stawkę"
    when "capacity"       then "liczbę miejsc"
    else field
    end
  end

  def format_event_change_value(field, raw)
    return "—" if raw.blank?
    case field
    when "scheduled_at", "ends_at"
      l(Time.zone.parse(raw), format: :short)
    when "pay_per_person"
      number_to_currency(raw.to_f)
    when "host_id"
      Host.find_by(id: raw)&.display_name || raw
    else
      raw
    end
  end
end
