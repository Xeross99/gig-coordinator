class WebPushNotifier < ApplicationJob
  queue_as :default

  # Message forms:
  #   perform(:completion, participation_id: 42)
  #   perform(:promotion,  participation_id: 42)
  #   perform(:new_event,  event_id: 7)
  #   perform(:invitation, event_id: 7, user_id: 3)
  #   perform(:mention,    message_id: 99, user_id: 3)
  def perform(kind, **args)
    case kind.to_sym
    when :completion, :promotion
      participation = Participation.find(args.fetch(:participation_id))
      payload = build_payload(kind, participation: participation)
      participation.user.push_subscriptions.find_each { |s| send_web_push(s, payload) }
    when :new_event
      event = Event.find(args.fetch(:event_id))
      payload = build_payload(:new_event, event: event)
      PushSubscription.find_each { |s| send_web_push(s, payload) }
    when :invitation
      event = Event.find(args.fetch(:event_id))
      user  = User.find(args.fetch(:user_id))
      payload = build_payload(:invitation, event: event)
      user.push_subscriptions.find_each { |s| send_web_push(s, payload) }
    when :mention
      message = Message.find(args.fetch(:message_id))
      user    = User.find(args.fetch(:user_id))
      payload = build_payload(:mention, message: message)
      user.push_subscriptions.find_each { |s| send_web_push(s, payload) }
    else
      raise ArgumentError, "unknown kind: #{kind}"
    end
  end

  private

  def build_payload(kind, participation: nil, event: nil, message: nil)
    helpers = Rails.application.routes.url_helpers
    url_for = ->(ev) { helpers.event_path(ev) }
    case kind.to_sym
    when :completion
      {
        title: "Event zakończony",
        body:  "Dziękujemy za pracę na \"#{participation.event.name}\".",
        url:   url_for.call(participation.event)
      }
    when :promotion
      {
        title: "Awansowałeś z listy rezerwowej",
        body:  "Zwolniło się miejsce na \"#{participation.event.name}\" - jesteś teraz potwierdzony!",
        url:   url_for.call(participation.event)
      }
    when :new_event
      {
        title: "Nowy event: #{event.name}",
        body:  "#{event.host.display_name} · #{ActionController::Base.helpers.number_to_currency(event.pay_per_person, unit: "zł", format: "%n %u")} · #{event.capacity} miejsc",
        url:   url_for.call(event)
      }
    when :invitation
      {
        title: "Zaproszenie: #{event.name}",
        body:  "Masz godzinę na potwierdzenie. Kliknij, żeby otworzyć event.",
        url:   url_for.call(event)
      }
    when :mention
      snippet = Nokogiri::HTML5.fragment(message.body).text.strip.truncate(140)
      {
        title: "#{message.user.display_name} oznaczył Cię w czacie",
        body:  snippet.presence || message.event.name,
        url:   helpers.event_path(message.event, anchor: "event_chat")
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
  rescue WebPush::ResponseError => e
    Rails.logger.warn("WebPush failed for sub #{subscription.id}: #{e.class} #{e.message}")
  end
end
