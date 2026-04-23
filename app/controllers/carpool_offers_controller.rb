class CarpoolOffersController < ApplicationController
  before_action :require_user!

  # POST /eventy/:event_id/podwozka
  def create
    @event = Event.find(params[:event_id])
    offer = @event.carpool_offers.build(user: Current.user)
    unless offer.save
      redirect_to event_path(@event), alert: offer.errors.full_messages.first || "Nie udało się zgłosić jako kierowca." and return
    end
    redirect_to event_path(@event), notice: "Jesteś kierowcą. Pasażerowie mogą teraz zapytać o podwózkę."
  end

  # DELETE /eventy/:event_id/podwozka
  def destroy
    @event = Event.find(params[:event_id])
    @event.carpool_offers.where(user_id: Current.user.id).destroy_all
    redirect_to event_path(@event), notice: "Rezygnacja z funkcji kierowcy potwierdzona."
  end
end
