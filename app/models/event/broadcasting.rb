module Event::Broadcasting
  extend ActiveSupport::Concern

  # Turbo Stream traffic on the `:events` feed stream. All synchronous — a feed
  # card is a single cheap render. Roster + counts broadcasts are a separate,
  # async story (EventRosterBroadcastJob, fired from Participation).

  FEED_CARD_FIELDS = %w[name pay_per_person capacity scheduled_at ends_at completed_at].freeze

  included do
    after_create_commit  :broadcast_feed_append,   if: :feed_visible_now?
    after_create_commit  :broadcast_visit_to_feed, if: :feed_visible_now?
    after_update_commit  :broadcast_feed_replace
    after_destroy_commit :broadcast_feed_remove
  end

  private

  # Sub-eventy NIE pojawiają się w feedzie `/eventy` (filtrowane po
  # `event_campaign_id: nil`) — więc nie powinny też wysyłać `:append`,
  # `:visit` ani `:remove` na `:events` stream. Inaczej `broadcast_visit_to_feed`
  # przy tworzeniu serii z N sub-eventami przerzucał twórcę na ostatni
  # sub-event zamiast zostawić go na stronie serii.
  def feed_visible_now?
    upcoming_now? && event_campaign_id.nil?
  end

  def broadcast_feed_append
    broadcast_prepend_to(
      :events,
      target: "events_list",
      partial: "events/event_card",
      locals: { event: self }
    )
  end

  def broadcast_feed_replace
    return if event_campaign_id.present?
    return unless saved_changes.keys.intersect?(FEED_CARD_FIELDS)

    broadcast_replace_to(
      :events,
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "events/event_card",
      locals: { event: self }
    )
  end

  def broadcast_feed_remove
    return if event_campaign_id.present?
    broadcast_remove_to(:events, target: ActionView::RecordIdentifier.dom_id(self))
  end

  # Push everyone currently on the user feed straight to the new event's page
  # (consumed by the `Turbo.StreamActions.visit` handler in application.js).
  def broadcast_visit_to_feed
    Turbo::StreamsChannel.broadcast_action_to(
      :events,
      action: :visit,
      target: Rails.application.routes.url_helpers.event_path(self)
    )
  end
end
