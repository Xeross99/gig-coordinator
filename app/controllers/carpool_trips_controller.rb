class CarpoolTripsController < ApplicationController
  include EventLockable

  before_action :set_offer

  # POST /eventy/:event_id/podwozka/trasa/depart
  # params[:pickup_order] — user_ids w kolejności odbierania z modalu (drag & drop).
  def depart
    @offer.depart!(params[:pickup_order])
    WebPushNotifier.perform_later(:carpool_departed, carpool_offer_id: @offer.id)
    redirect_to event_path(@event), notice: "Pasażerowie zostali powiadomieni, że wyjeżdżasz."
  end

  # POST /eventy/:event_id/podwozka/trasa/pickup
  # params[:user_id] — pasażer, którego kierowca aktualnie odbiera.
  def pickup
    pickup_user_id = params.require(:user_id).to_i
    target = @offer.accepted_requests.find { |r| r.user_id == pickup_user_id }&.user
    unless target
      redirect_to event_path(@event), alert: "Ten pasażer nie jest na liście Twojego auta." and return
    end

    @offer.arrive_at!(target)
    WebPushNotifier.perform_later(:carpool_at_pickup, carpool_offer_id: @offer.id, user_id: target.id)
    WebPushNotifier.perform_later(:carpool_progress,  carpool_offer_id: @offer.id, user_id: target.id)
    redirect_to event_path(@event), notice: "#{target.display_name} dostał powiadomienie."
  end

  # POST /eventy/:event_id/podwozka/trasa/cancel
  # Cicho — bez push do pasażerów. Semantyka „mam wszystkich, koniec trasy",
  # nie „wstrzymuję dojazd". Pasażerowie już są w aucie, nie ma kogo informować.
  def cancel
    @offer.cancel_trip!
    redirect_to event_path(@event), notice: "Trasa zakończona."
  end

  private

  def set_offer
    @offer = @event.carpool_offers.find_by(user_id: Current.user.id)
    return if @offer

    redirect_to event_path(@event), alert: "Nie jesteś kierowcą na tym evencie."
  end
end
