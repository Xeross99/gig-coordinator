class WebPushNotifier < ApplicationJob
  queue_as :default

  # Message format:
  #   perform(:completion, participation_id: 42)
  #   perform(:promotion,  participation_id: 42)
  def perform(kind, participation_id:)
    participation = Participation.find(participation_id)
    payload = build_payload(kind, participation)
    participation.user.push_subscriptions.find_each do |subscription|
      send_web_push(subscription, payload)
    end
  end

  private

  def build_payload(kind, participation)
    case kind
    when :completion
      {
        title: "Event zakończony",
        body:  "Dziękujemy za pracę na \"#{participation.event.name}\".",
        url:   Rails.application.routes.url_helpers.event_path(participation.event)
      }
    when :promotion
      {
        title: "Awansowałeś z listy rezerwowej",
        body:  "Zwolniło się miejsce na \"#{participation.event.name}\" — jesteś teraz potwierdzony!",
        url:   Rails.application.routes.url_helpers.event_path(participation.event)
      }
    else
      raise ArgumentError, "unknown kind: #{kind}"
    end
  end

  def send_web_push(subscription, payload)
    vapid = Rails.application.credentials.vapid
    return unless vapid&.public_key && vapid&.private_key

    WebPush.payload_send(
      message: payload.to_json,
      endpoint: subscription.endpoint,
      p256dh:   subscription.p256dh_key,
      auth:     subscription.auth_key,
      vapid: {
        subject:     vapid.subject || "mailto:admin@gig-coordinator.local",
        public_key:  vapid.public_key,
        private_key: vapid.private_key
      }
    )
  rescue WebPush::InvalidSubscription, WebPush::ExpiredSubscription
    subscription.destroy
  end
end
