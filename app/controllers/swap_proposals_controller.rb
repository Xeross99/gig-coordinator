class SwapProposalsController < ApplicationController
  before_action :require_user!

  def create
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)

    proposer_p = @event.participations.waitlist.find_by(user_id: Current.user.id)
    unless proposer_p
      redirect_to event_path(@event), alert: "Tylko osoby z listy rezerwowej mogą proponować wymianę." and return
    end

    if Current.user.blocked_from?(@event.host)
      redirect_to event_path(@event), alert: "Masz blokadę u tego gospodarza - nie możesz zapisać się na to zlecenie." and return
    end

    target_user = User.find(params[:target_user_id])
    target_p = @event.participations.confirmed.find_by(user_id: target_user.id)
    unless target_p
      redirect_to event_path(@event), alert: "Można proponować wymianę tylko potwierdzonej osobie." and return
    end

    if SwapProposal.pending.exists?(event: @event, proposer: Current.user, target: target_user)
      redirect_to event_path(@event), alert: "Masz już oczekującą propozycję wymiany dla tej osoby." and return
    end

    proposal = @event.swap_proposals.build(
      proposer: Current.user,
      target: target_user,
      expires_at: SwapProposal::EXPIRATION_WINDOW.from_now
    )

    if proposal.save
      WebPushNotifier.perform_later(:swap_proposal, swap_proposal_id: proposal.id)
      redirect_to event_path(@event), notice: "Propozycja wymiany wysłana."
    else
      redirect_to event_path(@event), alert: proposal.errors.full_messages.first
    end
  end

  def accept
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)

    @proposal = @event.swap_proposals.find_by(id: params[:id])

    unless @proposal&.pending?
      redirect_to event_path(@event), alert: "Warunki wymiany się zmieniły. Spróbuj ponownie." and return
    end

    unless @proposal.target_id == Current.user.id
      redirect_to event_path(@event), alert: "To nie jest Twoja propozycja wymiany." and return
    end

    if @proposal.time_expired?
      @proposal.update!(status: :expired)
      redirect_to event_path(@event), alert: "Propozycja wymiany wygasła." and return
    end

    if @proposal.accept!
      WebPushNotifier.perform_later(:swap_accepted, swap_proposal_id: @proposal.id)
      redirect_to event_path(@event), notice: "Wymiana zaakceptowana!"
    else
      redirect_to event_path(@event), alert: "Warunki wymiany się zmieniły. Spróbuj ponownie."
    end
  end

  def decline
    @event = Event.find(params[:event_id])
    return if enforce_event_lock!(@event)

    @proposal = @event.swap_proposals.find_by(id: params[:id])

    unless @proposal&.pending?
      redirect_to event_path(@event), alert: "Warunki wymiany się zmieniły. Spróbuj ponownie." and return
    end

    unless @proposal.target_id == Current.user.id
      redirect_to event_path(@event), alert: "To nie jest Twoja propozycja wymiany." and return
    end

    @proposal.update!(status: :declined)
    WebPushNotifier.perform_later(:swap_declined, swap_proposal_id: @proposal.id)
    redirect_to event_path(@event), notice: "Propozycja odrzucona."
  end
end
