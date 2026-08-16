class ParticipationsController < ApplicationController
  before_action :require_user!

  # POST /eventy/:event_id/uczestnictwo
  def create
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    unless Current.user.can_join_events?
      redirect_to event_path(@event), alert: "Jako Żółtodziób przeglądasz zlecenia, ale nie zapisujesz się na nie. Po awansie odzyskasz przycisk „Akceptuję”." and return
    end
    if Current.user.blocked_from?(@event.host)
      redirect_to event_path(@event), alert: "Masz blokadę u tego gospodarza - nie możesz zapisać się na to zlecenie." and return
    end

    resulting_status = nil

    Event.transaction do
      @event.lock!
      existing = @event.participations.find_by(user_id: Current.user.id)
      if existing.nil?
        status, position = next_slot_for(@event)
        @event.participations.create!(user: Current.user, status: status, position: position)
        resulting_status = status
      elsif existing.cancelled? || (existing.reserved? && existing.reservation_expired?)
        # `reserved + expired` traktujemy jak cancelled — sweeper job mógł
        # jeszcze nie zdążyć, a user klika „Akceptuję" w widoku, który już
        # pokazuje generyczny przycisk (bo reservation_expired? = true).
        status, position = next_slot_for(@event)
        existing.update!(status: status, position: position, reserved_until: nil)
        resulting_status = status
      end
      # confirmed/waitlist/aktywne reserved — no-op (dedykowane akcje accept/decline).
    end

    respond_to do |format|
      format.turbo_stream do
        streams = [
          turbo_stream.replace(ActionView::RecordIdentifier.dom_id(@event, :participation),
                               partial: "events/participation_button",
                               locals: { event: @event })
        ]
        streams << turbo_stream.append_all("body", %(<div data-controller="confetti"></div>).html_safe) if resulting_status == :confirmed
        render turbo_stream: streams
      end
      format.html do
        flash[:confetti] = true if resulting_status == :confirmed
        redirect_to event_path(@event)
      end
    end
  end

  # DELETE /eventy/:event_id/uczestnictwo
  # Wypisanie z sub-eventu serii jest dozwolone — user zostaje w primary
  # rosterze serii, ale ten konkretny termin pomija. Cancelled-row chroni
  # przed re-cascade'em z serii (cascader pomija usery, które już mają
  # participation w sub-evencie, niezależnie od statusu).
  def destroy
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)

    # Promocja z waitlisty + resequence + powiadomienia dzieją się w modelu
    # (Participation#refill_after_cancellation) — jedna ścieżka dla kontrolera,
    # API i konsoli.
    Event.transaction do
      @event.lock!
      participation = @event.participations.active.find_by(user_id: Current.user.id)
      participation&.update!(status: :cancelled, reserved_until: nil)
    end

    redirect_to event_path(@event)
  end

  # POST /eventy/:event_id/uczestnictwo/accept
  # User accepts a reservation offered by the priority seeding.
  # Wszyscy mistrzowie dostają zaproszenie na seedzie, więc gdy ktoś inny
  # zdąży pierwszy capacity może być już wyczerpane — wtedy spadamy na
  # waitlistę zamiast wybuchnąć ponad capacity.
  def accept
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    unless Current.user.can_join_events?
      redirect_to event_path(@event), alert: "Jako Żółtodziób przeglądasz zlecenia, ale nie zapisujesz się na nie. Po awansie odzyskasz przycisk „Akceptuję”." and return
    end
    result = nil

    Event.transaction do
      @event.lock!
      p = @event.participations.reserved.find_by(user_id: Current.user.id)
      if p && !p.reservation_expired?
        if @event.participations.confirmed.count < @event.capacity
          pos = (@event.participations.confirmed.maximum(:position) || 0) + 1
          p.update!(status: :confirmed, position: pos, reserved_until: nil)
          result = :confirmed
        else
          pos = (@event.participations.waitlist.maximum(:position) || 0) + 1
          p.update!(status: :waitlist, position: pos, reserved_until: nil)
          result = :waitlist
        end
      end
    end

    flash[:confetti] = true if result == :confirmed
    notice = case result
    when :confirmed then "Potwierdzone - do zobaczenia na zleceniu!"
    when :waitlist  then "Lista jest pełna - jesteś na liście rezerwowej."
    end
    redirect_to event_path(@event), notice: notice
  end

  # POST /eventy/:event_id/uczestnictwo/decline
  # User declines a reservation; system invites the next highest-rank user
  # (or promotes from waitlist if the ranking pool is exhausted).
  def decline
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)

    # refill_one + resequence robi model (reserved→cancelled).
    Event.transaction do
      @event.lock!
      p = @event.participations.reserved.find_by(user_id: Current.user.id)
      p&.update!(status: :cancelled, reserved_until: nil)
    end

    redirect_to event_path(@event), notice: "Odrzucone. Slot idzie do następnego w kolejce."
  end

  private

  # Regular join (via "Akceptuję"/"Dołącz na listę rezerwową" button). Reserved
  # slots count toward capacity — a user picking up a manual slot only gets
  # :confirmed if there's room after reservations are subtracted.
  def next_slot_for(event)
    if event.slots_taken < event.capacity
      next_position = (event.participations.confirmed.maximum(:position) || 0) + 1
      [ :confirmed, next_position ]
    else
      next_position = (event.participations.waitlist.maximum(:position) || 0) + 1
      [ :waitlist, next_position ]
    end
  end
end
