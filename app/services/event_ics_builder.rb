class EventIcsBuilder
  # Buduje plik iCalendar (RFC 5545) z dowolnej kolekcji eventów. UID jest
  # deterministyczny (`event-#{id}@host`) — ponowny import / refresh
  # subskrypcji aktualizuje istniejący wpis zamiast duplikować. Daty w UTC
  # w formacie basic ISO 8601 (`YYYYMMDDTHHMMSSZ`), CRLF jako separator linii,
  # escape `\,;\n` przez backslash. `X-WR-CALNAME` ustawia widoczną nazwę
  # kalendarza w Apple Calendar / Google Calendar.
  def self.build(events, calendar_name: "Gig Coordinator")
    events = Array(events).reject(&:nil?)
    domain = (Rails.application.config.action_mailer.default_url_options[:host].presence || "gig-coordinator.local")

    lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Gig Coordinator//PL",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "X-WR-CALNAME:#{escape(calendar_name)}",
      "X-WR-TIMEZONE:Europe/Warsaw"
    ]

    events.each do |event|
      description = [
        "Gospodarz: #{event.host.display_name}",
        "Stawka: #{format_pln(event.pay_per_person)} / osoba"
      ].join("\n")

      lines.concat([
        "BEGIN:VEVENT",
        "UID:event-#{event.id}@#{domain}",
        "DTSTAMP:#{utc(Time.current)}",
        "DTSTART:#{utc(event.scheduled_at)}",
        "DTEND:#{utc(event.ends_at)}",
        "SUMMARY:#{escape(event.name)}",
        "LOCATION:#{escape(event.host.location)}",
        "DESCRIPTION:#{escape(description)}",
        "END:VEVENT"
      ])
    end

    lines << "END:VCALENDAR"
    lines.join("\r\n") + "\r\n"
  end

  def self.utc(time)
    time.utc.strftime("%Y%m%dT%H%M%SZ")
  end

  def self.escape(text)
    text.to_s.gsub("\\", "\\\\").gsub(/[,;]/) { |c| "\\#{c}" }.gsub("\n", "\\n")
  end

  def self.format_pln(amount)
    "#{amount.to_i} zł"
  end
end
