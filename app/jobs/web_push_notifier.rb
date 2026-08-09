class WebPushNotifier < ApplicationJob
  queue_as :default

  # Wysyłka jest I/O-bound (HTTP do FCM/APNs) — 16 wątków skaluje niemal
  # liniowo do limitu WebPushPool::POOL_SIZE (musi być >= CONCURRENT_SENDS,
  # inaczej wątki czekają na połączenie z puli).
  CONCURRENT_SENDS = 16
  # Duży broadcast nie może być ucinany w połowie — 60s obcinało kolejkę
  # przy setkach subskrypcji. 10 min to bezpieczny sufit awaryjny.
  SEND_DRAIN_TIMEOUT = 600

  # JWT VAPID zależy wyłącznie od originu serwera push (aud = scheme://host)
  # i kluczy — NIE od subskrypcji. Gem podpisuje ES256 od nowa dla każdego
  # requestu (czysty koszt CPU × N przy broadcaście), więc trzymamy jeden
  # gotowy nagłówek Authorization per origin. Gem wystawia exp = 12h;
  # odświeżamy po 11h z marginesem.
  VAPID_HEADER_TTL = 11.hours

  @vapid_headers = {}
  @vapid_header_mutex = Mutex.new

  class << self
    def vapid_authorization(origin, **vapid_options)
      @vapid_header_mutex.synchronize do
        entry = @vapid_headers[origin]
        return entry[:header] if entry && entry[:expires_at].future?

        header = WebPush::Request.new(
          message: "", subscription: { endpoint: origin }, vapid: vapid_options
        ).build_vapid_header
        @vapid_headers[origin] = { header: header, expires_at: VAPID_HEADER_TTL.from_now }
        header
      end
    end
  end

  # Message forms:
  #   perform(:completion, participation_id: 42)
  #   perform(:promotion,  participation_id: 42)
  #   perform(:new_event,  event_id: 7)
  #   perform(:new_event,  event_id: 7, titles: %w[zoltodziob])
  #   perform(:invitation, event_id: 7, user_id: 3)
  #   perform(:test,       user_id: 3)
  def perform(kind, **args)
    @skip_web_push = Rails.env.development?
    Rails.logger.info("[Push] #{kind} started at #{Time.current.iso8601(3)}")

    case kind.to_sym
    when :test
      user = User.find(args.fetch(:user_id))
      payload = build_payload(:test)
      send_all(user.push_subscriptions, payload)
    when :premium_granted
      user = User.find_by(id: args.fetch(:user_id))
      return unless user&.premium?

      payload = build_payload(:premium_granted)
      send_all(user.push_subscriptions, payload)
    when :completion, :promotion
      participation = Participation.find(args.fetch(:participation_id))
      payload = build_payload(kind, participation: participation)
      send_all(participation.user.push_subscriptions, payload)
    when :new_event
      # Re-check: the delayed wave (zoltodziob, 5 min po utworzeniu) nie powinna
      # pingować o evencie, który został usunięty, już się rozpoczął albo zapełnił
      # się w międzyczasie. Na natychmiastowej fali te warunki i tak są spełnione.
      event = Event.find_by(id: args.fetch(:event_id))
      return unless event && event.scheduled_at&.future? && !event.full?

      payload = build_payload(:new_event, event: event)
      subs = PushSubscription.all
      if (titles = args[:titles]).present?
        title_ints = User.titles.values_at(*titles).compact
        subs = subs.joins(:user).where(users: { title: title_ints })
      end
      send_all(subs, payload)
    when :invitation
      event = Event.find(args.fetch(:event_id))
      user  = User.find(args.fetch(:user_id))
      payload = build_payload(:invitation, event: event)
      send_all(user.push_subscriptions, payload)
    when :event_changed
      event = Event.find_by(id: args.fetch(:event_id))
      return unless event && event.scheduled_at&.future?

      changed_fields = args.fetch(:changed_fields).map(&:to_s)
      payload = build_payload(:event_changed, event: event, changed_fields: changed_fields)
      send_all(PushSubscription.all, payload)
    when :new_campaign
      campaign = EventCampaign.find_by(id: args.fetch(:event_campaign_id))
      return unless campaign && !campaign.completed?

      payload = build_payload(:new_campaign, event_campaign: campaign)
      subs = PushSubscription.all
      if (titles = args[:titles]).present?
        title_ints = User.titles.values_at(*titles).compact
        subs = subs.joins(:user).where(users: { title: title_ints })
      end
      send_all(subs, payload)
    when :campaign_invitation
      campaign = EventCampaign.find(args.fetch(:event_campaign_id))
      user     = User.find(args.fetch(:user_id))
      payload  = build_payload(:campaign_invitation, event_campaign: campaign)
      send_all(user.push_subscriptions, payload)
    when :campaign_promotion
      cp = CampaignParticipation.find(args.fetch(:campaign_participation_id))
      payload = build_payload(:campaign_promotion, campaign_participation: cp)
      send_all(cp.user.push_subscriptions, payload)
    when :campaign_completion
      cp = CampaignParticipation.find(args.fetch(:campaign_participation_id))
      payload = build_payload(:campaign_completion, campaign_participation: cp)
      send_all(cp.user.push_subscriptions, payload)
    when :sub_event_added
      event = Event.find_by(id: args.fetch(:event_id))
      return unless event && event.event_campaign && event.scheduled_at&.future?

      payload = build_payload(:sub_event_added, event: event)
      campaign = event.event_campaign
      member_ids = campaign.campaign_participations.confirmed.pluck(:user_id)
      send_all(PushSubscription.where(user_id: member_ids), payload)
    when :carpool_ask, :carpool_accepted, :carpool_declined
      req = CarpoolRequest.find_by(id: args[:carpool_request_id])
      return unless req
      recipient = kind.to_sym == :carpool_ask ? req.carpool_offer.user : req.user
      payload = build_payload(kind, carpool_request: req)
      send_all(recipient.push_subscriptions, payload)
    when :carpool_offered
      offer = CarpoolOffer.find_by(id: args.fetch(:carpool_offer_id))
      return unless offer && !offer.event.started?
      payload = build_payload(:carpool_offered, carpool_offer: offer)
      # Główna lista (confirmed) tego zlecenia, bez samego kierowcy.
      member_ids = offer.event.participations.confirmed.where.not(user_id: offer.user_id).pluck(:user_id)
      send_all(PushSubscription.where(user_id: member_ids), payload)
    when :carpool_departed
      offer = CarpoolOffer.find_by(id: args.fetch(:carpool_offer_id))
      return unless offer
      # Treść mówi, po kogo kierowca jedzie najpierw („po Ciebie" vs „po: X"),
      # więc wysyłka idzie per pasażer zamiast jednego send_all.
      offer.carpool_requests.accepted.includes(:user).each do |req|
        payload = build_payload(kind, carpool_offer: offer, target_user: req.user)
        send_all(req.user.push_subscriptions, payload)
      end
    when :carpool_at_pickup
      offer = CarpoolOffer.find_by(id: args.fetch(:carpool_offer_id))
      pickup_user = User.find_by(id: args.fetch(:user_id))
      return unless offer && pickup_user
      payload = build_payload(:carpool_at_pickup, carpool_offer: offer, target_user: pickup_user)
      send_all(pickup_user.push_subscriptions, payload)
    when :carpool_progress
      offer = CarpoolOffer.find_by(id: args.fetch(:carpool_offer_id))
      pickup_user = User.find_by(id: args.fetch(:user_id))
      return unless offer && pickup_user
      payload = build_payload(:carpool_progress, carpool_offer: offer, target_user: pickup_user)
      other_ids = offer.accepted_requests.pluck(:user_id) - [ pickup_user.id ]
      send_all(PushSubscription.where(user_id: other_ids), payload)
    when :swap_proposal
      proposal = SwapProposal.find_by(id: args.fetch(:swap_proposal_id))
      return unless proposal&.pending?
      payload = build_payload(:swap_proposal, swap_proposal: proposal)
      send_all(proposal.target.push_subscriptions, payload)
    when :swap_accepted
      proposal = SwapProposal.find_by(id: args.fetch(:swap_proposal_id))
      return unless proposal&.accepted?
      payload = build_payload(:swap_accepted, swap_proposal: proposal)
      send_all(proposal.proposer.push_subscriptions, payload)
    when :swap_declined
      proposal = SwapProposal.find_by(id: args.fetch(:swap_proposal_id))
      return unless proposal&.declined?
      payload = build_payload(:swap_declined, swap_proposal: proposal)
      send_all(proposal.proposer.push_subscriptions, payload)
    when :event_reminder
      event = Event.find_by(id: args.fetch(:event_id))
      return unless event && !event.started?

      # Payload jest spersonalizowany (imię w treści), więc wysyłka idzie
      # per uczestnik zamiast jednego send_all na wszystkie subskrypcje.
      event.participations.confirmed.includes(:user).each do |participation|
        payload = build_payload(:event_reminder, participation: participation)
        send_all(participation.user.push_subscriptions, payload)
      end
    else
      raise ArgumentError, "unknown kind: #{kind}"
    end

    Rails.logger.info("[Push] #{kind} done at #{Time.current.iso8601(3)}")
  end

  private

  def build_payload(kind, participation: nil, event: nil, carpool_request: nil, carpool_offer: nil, target_user: nil, event_campaign: nil, campaign_participation: nil, changed_fields: nil, swap_proposal: nil)
    helpers = Rails.application.routes.url_helpers
    url_for = ->(ev) { helpers.event_path(ev) }
    campaign_url = ->(c) { helpers.event_campaign_path(c) }
    case kind.to_sym
    when :test
      {
        title: "Test powiadomień",
        body:  "Powiadomienia push działają poprawnie.",
        url:   helpers.edit_profile_path
      }
    when :premium_granted
      {
        title: "Dziękujemy za wsparcie aplikacji! 💛",
        body:  "Masz już konto premium — wejdź w Mój profil i wybierz swoją kartę pracownika.",
        url:   helpers.edit_profile_path
      }
    when :completion
      {
        title: "Zlecenie zakończone",
        body:  "Dziękujemy za pracę na \"#{participation.event.name}\".",
        url:   url_for.call(participation.event)
      }
    when :promotion
      {
        title: "Awansowałeś z listy rezerwowej",
        body:  "Zwolniło się miejsce na \"#{participation.event.name}\" - jesteś teraz na liście głównej",
        url:   url_for.call(participation.event)
      }
    when :new_event
      {
        title: "Nowy zlecenie: #{event.name}",
        body:  "#{event.host.display_name} · #{ActionController::Base.helpers.number_to_currency(event.pay_per_person, unit: "zł", format: "%n %u")} · #{event.capacity} miejsc",
        url:   url_for.call(event)
      }
    when :invitation
      {
        title: "Zaproszenie: #{event.name}",
        body:  "Masz godzinę na potwierdzenie. Kliknij, żeby otworzyć zlecenie.",
        url:   url_for.call(event)
      }
    when :event_changed
      labels = (changed_fields || []).map { |f| event_change_field_label(f) }
      {
        title: "Zmiana w #{event.name}",
        body:  "Zmieniono: #{labels.join(', ')}.",
        url:   url_for.call(event)
      }
    when :new_campaign
      sub_count = event_campaign.events.count
      {
        title: "Nowa seria zleceń: #{event_campaign.name}",
        body:  "#{event_campaign.host.display_name} · #{event_campaign.capacity} miejsc · #{sub_count} zleceń",
        url:   campaign_url.call(event_campaign)
      }
    when :campaign_invitation
      {
        title: "Zaproszenie do serii zleceń: #{event_campaign.name}",
        body:  "Masz 2,5 godziny na potwierdzenie miejsca w stałym składzie.",
        url:   campaign_url.call(event_campaign)
      }
    when :campaign_promotion
      campaign = campaign_participation.event_campaign
      {
        title: "Awansowałeś z listy rezerwowej serii zleceń",
        body:  "Zwolniło się miejsce w serii \"#{campaign.name}\" - jesteś teraz na liście głównej.",
        url:   campaign_url.call(campaign)
      }
    when :campaign_completion
      campaign = campaign_participation.event_campaign
      {
        title: "Seria zleceń zakończona",
        body:  "Dziękujemy za pracę w \"#{campaign.name}\".",
        url:   campaign_url.call(campaign)
      }
    when :event_reminder
      ev = participation.event
      {
        title: "Za godzinę: #{ev.name}",
        body:  "Hej #{participation.user.first_name}! O #{ev.scheduled_at.strftime('%H:%M')} zaczynamy zlecenie u gospodarza #{ev.host.display_name}. Widzimy się na miejscu! 🐔",
        url:   url_for.call(ev)
      }
    when :sub_event_added
      campaign = event.event_campaign
      {
        title: "Nowy termin w \"#{campaign.name}\"",
        body:  "#{event.name} - #{I18n.l(event.scheduled_at, format: :long)}",
        url:   url_for.call(event)
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
    when :carpool_offered
      driver = carpool_offer.user
      ev     = carpool_offer.event
      where  = ev.event_campaign ? "#{ev.name} (seria \"#{ev.event_campaign.name}\")" : "\"#{ev.name}\""
      {
        title: "Nowa podwózka",
        body:  "#{driver.display_name} oferuje się jako kierowca na #{where}.",
        url:   helpers.event_path(ev)
      }
    when :carpool_departed
      driver = carpool_offer.user
      ev     = carpool_offer.event
      first  = carpool_offer.first_pickup_user
      body = if first && target_user && first.id == target_user.id
        "#{driver.display_name} wyjechał - jedzie najpierw po Ciebie!"
      elsif first
        "#{driver.display_name} wyjechał - najpierw jedzie po: #{first.display_name}."
      else
        "#{driver.display_name} wyjechał - odbierze Cię niedługo."
      end
      {
        title: "Kierowca wyjechał",
        body:  body,
        url:   helpers.event_path(ev)
      }
    when :carpool_at_pickup
      driver = carpool_offer.user
      ev     = carpool_offer.event
      {
        title: "Kierowca czeka pod Twoim domem",
        body:  "#{driver.display_name} przyjechał - wsiadaj.",
        url:   helpers.event_path(ev)
      }
    when :carpool_progress
      driver = carpool_offer.user
      ev     = carpool_offer.event
      {
        title: "Kierowca w trasie",
        body:  "#{driver.display_name} jest teraz u: #{target_user.display_name}.",
        url:   helpers.event_path(ev)
      }
    when :swap_proposal
      {
        title: "Propozycja wymiany",
        body:  "#{swap_proposal.proposer.display_name} chce się z Tobą zamienić na \"#{swap_proposal.event.name}\".",
        url:   url_for.call(swap_proposal.event)
      }
    when :swap_accepted
      {
        title: "Wymiana zaakceptowana!",
        body:  "#{swap_proposal.target.display_name} zaakceptował wymianę na \"#{swap_proposal.event.name}\". Jesteś teraz potwierdzony!",
        url:   url_for.call(swap_proposal.event)
      }
    when :swap_declined
      {
        title: "Wymiana odrzucona",
        body:  "#{swap_proposal.target.display_name} odrzucił propozycję wymiany na \"#{swap_proposal.event.name}\".",
        url:   url_for.call(swap_proposal.event)
      }
    else
      raise ArgumentError, "unknown kind: #{kind}"
    end
  end

  def send_all(subscriptions, payload)
    # Wyłączone konta nie dostają pushy — jeden centralny filtr zamiast
    # pilnowania każdej gałęzi perform.
    subscriptions = subscriptions.joins(:user).merge(User.enabled)

    send_batch(subscriptions, payload)
  end

  def send_batch(subscriptions, payload)
    pool = Concurrent::FixedThreadPool.new(CONCURRENT_SENDS)
    subscriptions.find_each do |sub|
      pool.post do
        Rails.application.executor.wrap { send_web_push(sub, payload) }
      rescue => e
        Rails.logger.error("WebPush thread error for sub #{sub.id}: #{e.class} #{e.message}")
      end
    end
  ensure
    if pool
      pool.shutdown
      unless pool.wait_for_termination(SEND_DRAIN_TIMEOUT)
        Rails.logger.warn("[Push] web push drain timeout after #{SEND_DRAIN_TIMEOUT}s — part of the batch was dropped")
        pool.kill
      end
    end
  end

  MAX_SEND_ATTEMPTS = 3

  def send_web_push(subscription, payload, attempt: 1)
    return if @skip_web_push
    vapid = vapid_credentials
    return unless vapid&.public_key && vapid&.private_key

    deliver_push(subscription, payload, vapid)
  rescue WebPush::InvalidSubscription, WebPush::ExpiredSubscription
    subscription.destroy
  rescue WebPush::ResponseError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET => e
    if attempt < MAX_SEND_ATTEMPTS
      sleep(attempt * 0.2)
      send_web_push(subscription, payload, attempt: attempt + 1)
    else
      Rails.logger.warn("WebPush failed for sub #{subscription.id} after #{MAX_SEND_ATTEMPTS} attempts: #{e.class} #{e.message}")
    end
  end

  # Credentials liczone raz per job — zależą tylko od konfiguracji, nie od
  # odbiorcy. Payloadu NIE wolno tak memoizować (patrz message_json).
  def vapid_credentials
    return @vapid_credentials if defined?(@vapid_credentials)
    @vapid_credentials = Rails.application.credentials.vapid
  end

  # Celowo BEZ memoizacji — jeden perform może wysyłać różne payloady
  # (:event_reminder i :carpool_departed personalizują treść per odbiorca).
  # `@message_json ||=` serwowało każdemu kolejnemu odbiorcy treść pierwszego.
  def message_json(payload)
    payload.to_json
  end

  def deliver_push(subscription, payload, vapid)
    uri = URI.parse(subscription.endpoint)

    # vapid: {} — gem nie buduje wtedy nagłówka Authorization (i nie podpisuje
    # JWT per request); wstrzykujemy nagłówek z cache per origin. Szyfrowanie
    # payloadu (RFC 8291) pozostaje per subskrypcja — tego nie da się dzielić.
    request = WebPush::Request.new(
      message: message_json(payload),
      subscription: {
        endpoint: subscription.endpoint,
        keys: { p256dh: subscription.p256dh_key, auth: subscription.auth_key }
      },
      vapid: {}
    )

    headers = request.headers
    headers["Authorization"] = self.class.vapid_authorization(
      "#{uri.scheme}://#{uri.host}",
      subject:     vapid.subject || "mailto:admin@chicken.local",
      public_key:  vapid.public_key,
      private_key: vapid.private_key
    )

    WebPushPool.with_connection(uri) do |http|
      post = Net::HTTP::Post.new(uri.request_uri, headers)
      post.body = request.body
      verify_push_response(http.request(post), uri.host)
    end
  end

  def verify_push_response(resp, host)
    case resp
    when Net::HTTPSuccess then resp
    when Net::HTTPGone then raise WebPush::ExpiredSubscription.new(resp, host)
    when Net::HTTPNotFound then raise WebPush::InvalidSubscription.new(resp, host)
    when Net::HTTPUnauthorized, Net::HTTPForbidden
      raise WebPush::Unauthorized.new(resp, host)
    when Net::HTTPBadRequest
      raise resp.message == "UnauthorizedRegistration" ?
        WebPush::Unauthorized.new(resp, host) : WebPush::ResponseError.new(resp, host)
    when Net::HTTPRequestEntityTooLarge then raise WebPush::PayloadTooLarge.new(resp, host)
    when Net::HTTPTooManyRequests then raise WebPush::TooManyRequests.new(resp, host)
    when Net::HTTPServerError then raise WebPush::PushServiceError.new(resp, host)
    else raise WebPush::ResponseError.new(resp, host)
    end
  end

  FIELD_LABELS = {
    "name" => "nazwę", "host_id" => "gospodarza", "scheduled_at" => "datę startu",
    "ends_at" => "datę zakończenia", "pay_per_person" => "stawkę", "capacity" => "liczbę miejsc"
  }.freeze

  def event_change_field_label(field)
    FIELD_LABELS[field] || field
  end
end
