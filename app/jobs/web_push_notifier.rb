class WebPushNotifier < ApplicationJob
  queue_as :default

  # Message forms:
  #   perform(:completion, participation_id: 42)
  #   perform(:promotion,  participation_id: 42)
  #   perform(:new_event,  event_id: 7)
  #   perform(:new_event,  event_id: 7, titles: %w[rookie])
  #   perform(:invitation, event_id: 7, user_id: 3)
  #   perform(:mention,    message_id: 99, user_id: 3)
  def perform(kind, **args)
    case kind.to_sym
    when :completion, :promotion
      participation = Participation.find(args.fetch(:participation_id))
      payload = build_payload(kind, participation: participation)
      participation.user.push_subscriptions.find_each { |s| send_web_push(s, payload) }
    when :new_event
      # Re-check: the delayed wave (rookie, 5 min po utworzeniu) nie powinna
      # pingować o evencie, który został usunięty, już się rozpoczął albo zapełnił
      # się w międzyczasie. Na natychmiastowej fali te warunki i tak są spełnione.
      event = Event.find_by(id: args.fetch(:event_id))
      return unless event && event.scheduled_at&.future? && !event.full?

      payload = build_payload(:new_event, event: event)
      subs    = PushSubscription.all
      if (titles = args[:titles]).present?
        title_ints = User.titles.values_at(*titles).compact
        subs = subs.joins(:user).where(users: { title: title_ints })
      end
      subs.find_each { |s| send_web_push(s, payload) }
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
    when :carpool_ask, :carpool_accepted, :carpool_declined
      req = CarpoolRequest.find_by(id: args.fetch(:carpool_request_id))
      return unless req
      recipient = kind.to_sym == :carpool_ask ? req.carpool_offer.user : req.user
      payload = build_payload(kind, carpool_request: req)
      recipient.push_subscriptions.find_each { |s| send_web_push(s, payload) }
    else
      raise ArgumentError, "unknown kind: #{kind}"
    end
  end

  private

  def build_payload(kind, participation: nil, event: nil, message: nil, carpool_request: nil)
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
    when :carpool_ask
      ev = carpool_request.carpool_offer.event
      {
        title: "Prośba o podwózkę",
        body:  "#{carpool_request.user.display_name} pyta o miejsce w Twoim aucie na \"#{ev.name}\".",
        url:   helpers.event_path(ev)
      }
    when :carpool_accepted
      ev = carpool_request.carpool_offer.event
      {
        title: "Masz podwózkę!",
        body:  "#{carpool_request.carpool_offer.user.display_name} potwierdził podwózkę na \"#{ev.name}\".",
        url:   helpers.event_path(ev)
      }
    when :carpool_declined
      ev = carpool_request.carpool_offer.event
      {
        title: "Brak miejsca w aucie",
        body:  "#{carpool_request.carpool_offer.user.display_name} nie może Cię zabrać na \"#{ev.name}\".",
        url:   helpers.event_path(ev)
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
