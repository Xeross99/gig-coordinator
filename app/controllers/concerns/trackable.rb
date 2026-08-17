# Stamp the currently signed-in User with `last_seen_at` once per minute so
# the "online now" indicator + "ostatnio widziany" text in the UI stay fresh
# without writing to the DB on every request. The Session gets the same
# treatment (covers hosts too) — feeds „ostatnio aktywne" on the device
# list in the profile.
module Trackable
  extend ActiveSupport::Concern

  THROTTLE = 1.minute

  included do
    before_action :touch_last_seen
  end

  private

  def touch_last_seen
    touch_last_seen_on(Current.session)
    touch_last_seen_on(Current.user)
  end

  def touch_last_seen_on(record)
    return if record.nil?
    return if record.last_seen_at&.after?(THROTTLE.ago)

    record.update_column(:last_seen_at, Time.current)
  end
end
