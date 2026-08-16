class CarpoolMailer < ApplicationMailer
  def ask
    @request   = params[:carpool_request]
    @offer     = @request.carpool_offer
    @event     = @offer.event
    @driver    = @offer.user
    @passenger = @request.user

    mail to: @driver.email, subject: "Prośba o podwózkę: #{@passenger.display_name} (#{@event.name})"
  end

  def accepted
    @request   = params[:carpool_request]
    @offer     = @request.carpool_offer
    @event     = @offer.event
    @driver    = @offer.user
    @passenger = @request.user

    mail to: @passenger.email, subject: "Masz podwózkę na #{@event.name}"
  end

  def declined
    @request   = params[:carpool_request]
    @offer     = @request.carpool_offer
    @event     = @offer.event
    @driver    = @offer.user
    @passenger = @request.user

    mail to: @passenger.email, subject: "Brak miejsca w aucie na #{@event.name}"
  end
end
