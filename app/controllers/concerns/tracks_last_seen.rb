# Stamp the currently signed-in User with `last_seen_at` once per minute so
# the "online now" indicator + "ostatnio widziany" text in the UI stay fresh
# without writing to the DB on every request. The Session gets the same
# treatment (covers hosts too) — feeds „ostatnio aktywne" on the device
# list in the profile.
#
# Deliberately does NOT register the callback — the includer wires its own
# hook (ApplicationController runs it as a `before_action`).
module TracksLastSeen
  extend ActiveSupport::Concern

  private

  def touch_last_seen
    touch_session_last_seen
    return unless Current.user
    last = Current.user.last_seen_at
    return if last && last > 1.minute.ago
    Current.user.update_column(:last_seen_at, Time.current)
  end

  def touch_session_last_seen
    session = Current.session
    return unless session
    return if session.last_seen_at && session.last_seen_at > 1.minute.ago
    session.update_column(:last_seen_at, Time.current)
  end
end
