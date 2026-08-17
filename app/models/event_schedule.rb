# The form splits a schedule across `event_date`, `start_hour`/`start_minute`
# and `duration_hours`/`duration_minutes`; the model stores two plain datetimes.
# This is the only place that folds those fields back together — the split is
# purely a UI concern. Raw fields are deleted from `attrs` (Parameters or Hash)
# and replaced by `scheduled_at`/`ends_at`. Without a date and hour nothing is
# composed, so an incomplete submit leaves both columns untouched instead of
# silently producing today's midnight.
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
