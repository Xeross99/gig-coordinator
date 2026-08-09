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
  def history_entry_visuals(entry)
    plus_path  = "M10.75 4.75a.75.75 0 0 0-1.5 0v4.5h-4.5a.75.75 0 0 0 0 1.5h4.5v4.5a.75.75 0 0 0 1.5 0v-4.5h4.5a.75.75 0 0 0 0-1.5h-4.5v-4.5Z"
    pencil     = "M2.695 14.763l-1.262 3.154a.5.5 0 0 0 .65.65l3.155-1.262a4 4 0 0 0 1.343-.885L17.5 5.5a2.121 2.121 0 0 0-3-3L3.58 13.42a4 4 0 0 0-.885 1.343Z"
    check      = "M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z"
    x_circle   = "M8.28 7.22a.75.75 0 0 0-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 1 0 1.06 1.06L10 11.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L11.06 10l1.72-1.72a.75.75 0 0 0-1.06-1.06L10 8.94 8.28 7.22ZM10 1a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm-7.5 9a7.5 7.5 0 1 1 15 0 7.5 7.5 0 0 1-15 0Z"
    star       = "M10.868 2.884c-.321-.772-1.415-.772-1.736 0l-1.83 4.401-4.753.381c-.833.067-1.171 1.107-.536 1.651l3.62 3.102-1.106 4.637c-.194.813.691 1.456 1.405 1.02L10 15.591l4.069 2.485c.713.436 1.598-.207 1.404-1.02l-1.106-4.637 3.62-3.102c.635-.544.297-1.584-.536-1.65l-4.752-.382-1.831-4.401Z"
    arrow_up   = "M10 17a.75.75 0 0 1-.75-.75V5.612L5.29 9.77a.75.75 0 0 1-1.08-1.04l5.25-5.5a.75.75 0 0 1 1.08 0l5.25 5.5a.75.75 0 1 1-1.08 1.04L10.75 5.612V16.25A.75.75 0 0 1 10 17Z"
    clock      = "M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm.75-13a.75.75 0 0 0-1.5 0v5c0 .199.079.39.22.53l3 3a.75.75 0 1 0 1.06-1.06l-2.78-2.78V5Z"
    thumbs_up  = "M1 8.25a1.25 1.25 0 1 1 2.5 0v7.5a1.25 1.25 0 1 1-2.5 0v-7.5ZM11 3V1.7c0-.268.14-.526.395-.607A2 2 0 0 1 14 3c0 .995-.182 1.948-.514 2.826-.204.54.166 1.174.744 1.174h2.52c1.243 0 2.261 1.01 2.146 2.247a23.864 23.864 0 0 1-1.341 5.974C17.153 16.323 16.072 17 14.9 17h-3.192a3 3 0 0 1-1.341-.317l-2.734-1.366A3 3 0 0 0 6.292 15H5V8h.963c.685 0 1.258-.483 1.612-1.068a4.011 4.011 0 0 1 2.166-1.73c.432-.143.853-.386.853-.842V3Z"

    case entry[:kind]
    when :created            then [ "bg-stone-500", plus_path ]
    when :edited             then [ "bg-sky-500",   pencil    ]
    when :participation_event
      case entry[:participation_event].event_type
      when "joined"           then [ "bg-emerald-500", check     ]
      when "joined_waitlist"  then [ "bg-orange-500",  check     ]
      when "promoted"         then [ "bg-emerald-500", arrow_up  ]
      when "accepted"         then [ "bg-emerald-500", thumbs_up ]
      when "reserved"         then [ "bg-indigo-500",  star      ]
      when "declined"         then [ "bg-red-400",     x_circle  ]
      when "cancelled"        then [ "bg-red-400",     x_circle  ]
      when "expired"          then [ "bg-stone-400",   clock     ]
      when "swapped_in"       then [ "bg-indigo-500",  arrow_up  ]
      when "swapped_out"      then [ "bg-indigo-400",  x_circle  ]
      else                         [ "bg-stone-400",   clock     ]
      end
    else
      [ "bg-stone-400", clock ]
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

  # Polski opis pojedynczego ParticipationEvent (audit log). Wszyscy kurołapacze
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
