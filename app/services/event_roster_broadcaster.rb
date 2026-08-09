class EventRosterBroadcaster
  # Roster + carpool partial używa `Current.user` do renderowania UI specyficznego
  # dla zalogowanego usera (np. „Zapytania" + przyciski Potwierdź/Odrzuć dla
  # kierowcy vs. pasywne „N osób czeka" dla reszty, oraz panel trasy dla
  # pasażera vs. kierowcy). Ale broadcast leci raz, ten sam HTML do wszystkich
  # subskrybentów — z perspektywą tego, kto wywołał broadcast (np. pasażer
  # tworzący request). W efekcie kierowca w drugiej zakładce dostawał wersję
  # pasażerską i nie widział nowego zapytania.
  #
  # Rozwiązanie: każdy zalogowany worker subskrybuje TYLKO swój stream
  # `[event, user, :roster_personal]` (zob. `events/show.html.erb`). Broadcaster
  # wysyła:
  #   - generic do `[event, :roster]` — dla hostów (host_admin/events/show)
  #     oraz niezalogowanych viewerów. Wcześniej generic + per-user szły razem
  #     i ścigały się o ten sam target — race usunięty przez rozdzielenie
  #     odbiorców.
  #   - per-user do `[event, user, :roster_personal]` dla każdego usera
  #     z istotną rolą na evencie (uczestnicy + kierowcy + zaakceptowani
  #     pasażerowie). Userzy bez roli carpoolowej dostają render z `Current.user`
  #     ustawionym na nich (cancellation reasons + przyciski) — i tak partial
  #     przy braku roli daje ten sam HTML co default, ale wysyłamy do ich
  #     stream'u, żeby nadal dostawali real-time updates z ogólnego rostra.
  def self.broadcast(event)
    return unless event

    default_html = render_as(nil) do
      ApplicationController.render(partial: "events/roster", locals: { event: event })
    end

    Turbo::StreamsChannel.broadcast_replace_to(
      [ event, :roster ],
      target: ActionView::RecordIdentifier.dom_id(event, :roster),
      html: default_html
    )

    driver_ids    = event.carpool_offers.pluck(:user_id)
    passenger_ids = CarpoolRequest.joins(:carpool_offer)
                                  .where(carpool_offers: { event_id: event.id })
                                  .accepted
                                  .pluck(:user_id)
    waitlist_ids  = event.participations.waitlist.pluck(:user_id)
    confirmed_with_swap_ids = SwapProposal.pending
                                          .where(event: event)
                                          .where("expires_at > ?", Time.current)
                                          .pluck(:target_id)
    personal_ids  = (driver_ids + passenger_ids + waitlist_ids + confirmed_with_swap_ids).to_set

    # Wszyscy potencjalni viewerzy z osobistym streamem: aktywni uczestnicy
    # (confirmed/waitlist/reserved) + kierowcy + zaakceptowani pasażerowie.
    # Niezaangażowani (np. mistrz przeglądający randomowy event bez udziału)
    # i tak dostaną generic — bez własnego subskrybowania nie ma im czego
    # wysłać. Akceptowalny trade-off: real-time działa dla każdego, kto coś
    # robi w obrębie eventu.
    viewer_ids = (
      event.participations.where.not(status: :cancelled).pluck(:user_id) +
      driver_ids + passenger_ids
    ).uniq

    User.where(id: viewer_ids).find_each do |user|
      html = if personal_ids.include?(user.id)
        render_as(user) do
          ApplicationController.render(partial: "events/roster", locals: { event: event })
        end
      else
        default_html
      end

      Turbo::StreamsChannel.broadcast_replace_to(
        [ event, user, :roster_personal ],
        target: ActionView::RecordIdentifier.dom_id(event, :roster),
        html: html
      )
    end
  end

  # `Current.user` to read-only metoda derywowana z `Current.session` —
  # nie da się jej ustawić wprost. Podstawiamy więc fake-session z
  # `authenticatable: user` na czas renderu (lub czyścimy session dla
  # render-as-nobody).
  def self.render_as(user)
    prev_session = Current.session
    Current.session = user ? Session.new(authenticatable: user) : nil
    yield
  ensure
    Current.session = prev_session
  end
end
