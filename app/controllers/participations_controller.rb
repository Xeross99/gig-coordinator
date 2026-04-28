class ParticipationsController < ApplicationController
  before_action :require_user!

  # POST /eventy/:event_id/uczestnictwo
  def create
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    if Current.user.blocked_from?(@event.host)
      redirect_to event_path(@event), alert: I18n.t("participations.blocked") and return
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
  def destroy
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    promoted = nil
    cancel_blocked = false

    Event.transaction do
      @event.lock!
      participation = @event.participations.active.find_by(user_id: Current.user.id)
      if participation
        if participation.confirmed? && !@event.confirmed_cancellable?
          cancel_blocked = true
        else
          was_confirmed = participation.confirmed?
          participation.update!(status: :cancelled, reserved_until: nil)
          promoted = promote_from_waitlist(@event) if was_confirmed
        end
      end
    end

    if cancel_blocked
      redirect_to event_path(@event), alert: I18n.t("participations.cancel_locked_alert") and return
    end

    if promoted
      PromotionMailer.with(participation: promoted).notify.deliver_later
      WebPushNotifier.perform_later(:promotion, participation_id: promoted.id)
    end
    redirect_to event_path(@event)
  end

  # POST /eventy/:event_id/uczestnictwo/accept
  # User accepts a reservation offered by the priority seeding.
  def accept
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)
    accepted = false

    Event.transaction do
      @event.lock!
      p = @event.participations.reserved.find_by(user_id: Current.user.id)
      if p && !p.reservation_expired?
        pos = (@event.participations.confirmed.maximum(:position) || 0) + 1
        p.update!(status: :confirmed, position: pos, reserved_until: nil)
        accepted = true
      end
    end

    flash[:confetti] = true if accepted
    redirect_to event_path(@event), notice: "Potwierdzone - do zobaczenia na łapaniu!"
  end

  # POST /eventy/:event_id/uczestnictwo/decline
  # User declines a reservation; system invites the next highest-rank user
  # (or promotes from waitlist if the ranking pool is exhausted).
  def decline
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)

    Event.transaction do
      @event.lock!
      p = @event.participations.reserved.find_by(user_id: Current.user.id)
      p&.update!(status: :cancelled, reserved_until: nil)
    end

    ReservationService.refill_one(@event)
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

  def promote_from_waitlist(event)
    promoted = event.participations.waitlist.order(:position).first
    return nil unless promoted

    next_position = (event.participations.confirmed.maximum(:position) || 0) + 1
    promoted.update!(status: :confirmed, position: next_position)
    promoted
  end
end
