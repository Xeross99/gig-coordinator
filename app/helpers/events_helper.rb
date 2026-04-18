module EventsHelper
  def google_maps_embed_src(location)
    "https://maps.google.com/maps?q=#{CGI.escape(location.to_s)}&output=embed"
  end

  def google_maps_open_url(location)
    "https://www.google.com/maps/search/?api=1&query=#{CGI.escape(location.to_s)}"
  end

  # --- Event history timeline -------------------------------------------------

  # [bg-color-class, svg-path] pair keyed off the entry kind + participation
  # status. Icons are Heroicons mini paths (solid, 20×20 viewBox).
  def history_entry_visuals(entry)
    case entry[:kind]
    when :created
      [ "bg-stone-500", "M10.75 4.75a.75.75 0 0 0-1.5 0v4.5h-4.5a.75.75 0 0 0 0 1.5h4.5v4.5a.75.75 0 0 0 1.5 0v-4.5h4.5a.75.75 0 0 0 0-1.5h-4.5v-4.5Z" ]
    else
      case entry[:participation].status
      when "confirmed" then [ "bg-emerald-500", "M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" ]
      when "waitlist"  then [ "bg-amber-500",   "M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm.75-13a.75.75 0 0 0-1.5 0v5c0 .199.079.39.22.53l3 3a.75.75 0 1 0 1.06-1.06l-2.78-2.78V5Z" ]
      when "reserved"  then [ "bg-indigo-500",  "M10.868 2.884c-.321-.772-1.415-.772-1.736 0l-1.83 4.401-4.753.381c-.833.067-1.171 1.107-.536 1.651l3.62 3.102-1.106 4.637c-.194.813.691 1.456 1.405 1.02L10 15.591l4.069 2.485c.713.436 1.598-.207 1.404-1.02l-1.106-4.637 3.62-3.102c.635-.544.297-1.584-.536-1.65l-4.752-.382-1.831-4.401Z" ]
      when "cancelled" then [ "bg-red-400",     "M8.28 7.22a.75.75 0 0 0-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 1 0 1.06 1.06L10 11.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L11.06 10l1.72-1.72a.75.75 0 0 0-1.06-1.06L10 8.94 8.28 7.22ZM10 1a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm-7.5 9a7.5 7.5 0 1 1 15 0 7.5 7.5 0 0 1-15 0Z" ]
      else                  [ "bg-stone-400",   "M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16Z" ]
      end
    end
  end

  # HTML string (safe) describing what happened. The kind controls the template,
  # participation.status fills in the verb.
  def history_entry_text(entry)
    case entry[:kind]
    when :created
      safe_join([ "Utworzono wydarzenie przez ", tag.strong(entry[:host].display_name) ])
    when :joined
      safe_join([ tag.strong(entry[:participation].user.display_name), " ", participation_action_verb(entry[:participation].status, :initial) ])
    when :status_change
      safe_join([ tag.strong(entry[:participation].user.display_name), " ", participation_action_verb(entry[:participation].status, :update) ])
    end
  end

  def participation_action_verb(status, phase)
    case [ status, phase ]
    in [ "confirmed", :initial ] then "dołączył jako potwierdzony"
    in [ "confirmed", :update  ] then "został potwierdzony"
    in [ "waitlist",  :initial ] then "zapisał się na listę rezerwową"
    in [ "waitlist",  :update  ] then "przeniesiony na listę rezerwową"
    in [ "reserved",  :initial ] then "otrzymał zaproszenie"
    in [ "reserved",  :update  ] then "ponownie zaproszony"
    in [ "cancelled", :initial ] then "anulował udział"
    in [ "cancelled", :update  ] then "anulował udział"
    else "zmienił status"
    end
  end
end
