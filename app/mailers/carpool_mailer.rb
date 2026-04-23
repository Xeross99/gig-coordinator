class CarpoolMailer < ApplicationMailer
  # Pasażer poprosił o podwózkę → kierowca dostaje mail.
  def ask
    @request  = params[:carpool_request]
    @offer    = @request.carpool_offer
    @event    = @offer.event
    @driver   = @offer.user
    @passenger = @request.user
    mail to: @driver.email, subject: "Prośba o podwózkę: #{@passenger.display_name} (#{@event.name})"
  end

  # Kierowca potwierdził → pasażer dostaje mail.
  def accepted
    @request   = params[:carpool_request]
    @offer     = @request.carpool_offer
    @event     = @offer.event
    @driver    = @offer.user
    @passenger = @request.user
    mail to: @passenger.email, subject: "Masz podwózkę na #{@event.name}"
  end

  # Kierowca odrzucił → pasażer dostaje mail.
  def declined
    @request   = params[:carpool_request]
    @offer     = @request.carpool_offer
    @event     = @offer.event
    @driver    = @offer.user
    @passenger = @request.user
    mail to: @passenger.email, subject: "Brak miejsca w aucie na #{@event.name}"
  end
end
