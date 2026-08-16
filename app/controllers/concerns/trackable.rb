# Stamp the currently signed-in User with `last_seen_at` once per minute so
# the "online now" indicator + "ostatnio widziany" text in the UI stay fresh
# without writing to the DB on every request. The Session gets the same
# treatment (covers hosts too) — feeds „ostatnio aktywne" on the device
# list in the profile.
module Trackable
  extend ActiveSupport::Concern

  included do
    # MUSI być includowane PO Authenticatable — kolejność rejestracji filtrów
    # jest kolejnością wykonania, a ten czyta `Current.session`, którą ustawia
    # `load_current_session`. Odwrotnie byłby cichym no-opem: żadnego wyjątku,
    # tylko martwy wskaźnik „online" i pusta data na liście urządzeń.
    before_action :touch_last_seen
  end

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
