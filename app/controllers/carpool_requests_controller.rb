class CarpoolRequestsController < ApplicationController
  before_action :require_user!

  # POST /eventy/:event_id/podwozki-zapytania
  # params[:carpool_offer_id] identifies which driver the user wants to ride with.
  def create
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    offer = @event.carpool_offers.find(params.require(:carpool_offer_id))

    existing = offer.carpool_requests.find_by(user_id: Current.user.id)
    if existing
      # Deklinowane wcześniej zapytanie odradzamy jako pending, żeby user nie musiał
      # tworzyć nowego rekordu (i nie bił o uniqueness).
      if existing.declined?
        existing.update(status: :pending)
      end
      redirect_to event_path(@event) and return
    end

    req = offer.carpool_requests.build(user: Current.user, status: :pending)
    unless req.save
      redirect_to event_path(@event), alert: req.errors.full_messages.first || "Nie udało się wysłać zapytania." and return
    end

    CarpoolMailer.with(carpool_request: req).ask.deliver_later if offer.user.email.present?
    WebPushNotifier.perform_later(:carpool_ask, carpool_request_id: req.id)

    redirect_to event_path(@event), notice: "Zapytanie wysłane. Kierowca dostanie powiadomienie."
  end

  # POST /eventy/:event_id/podwozki-zapytania/:id/accept
  def accept
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    req = find_request_for_driver
    unless req
      redirect_to event_path(@event), alert: "Nie znaleziono zapytania." and return
    end

    if req.carpool_offer.seats_left < 1 && !req.accepted?
      redirect_to event_path(@event), alert: "Brak wolnych miejsc w aucie." and return
    end

    req.update!(status: :accepted)
    CarpoolMailer.with(carpool_request: req).accepted.deliver_later if req.user.email.present?
    WebPushNotifier.perform_later(:carpool_accepted, carpool_request_id: req.id)
    redirect_to event_path(@event), notice: "Potwierdzone. Pasażer dostanie powiadomienie."
  end

  # POST /eventy/:event_id/podwozki-zapytania/:id/decline
  def decline
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    req = find_request_for_driver
    unless req
      redirect_to event_path(@event), alert: "Nie znaleziono zapytania." and return
    end

    req.update!(status: :declined)
    CarpoolMailer.with(carpool_request: req).declined.deliver_later if req.user.email.present?
    WebPushNotifier.perform_later(:carpool_declined, carpool_request_id: req.id)
    redirect_to event_path(@event), notice: "Odrzucone."
  end

  # DELETE /eventy/:event_id/podwozki-zapytania/:id
  # Passenger withdraws their own request.
  def destroy
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    req = CarpoolRequest.joins(:carpool_offer)
                        .where(carpool_offers: { event_id: @event.id })
                        .where(user_id: Current.user.id, id: params[:id])
                        .first
    req&.destroy
    redirect_to event_path(@event), notice: "Zapytanie wycofane."
  end

  private

  # Driver-only guard: the signed-in user must own the offer that the request
  # belongs to. Keeps passengers from accepting/declining requests on someone
  # else's car.
  def find_request_for_driver
    CarpoolRequest.joins(:carpool_offer)
                  .where(carpool_offers: { event_id: @event.id, user_id: Current.user.id })
                  .find_by(id: params[:id])
  end
end
