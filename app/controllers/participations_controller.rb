class ParticipationsController < ApplicationController
  before_action :require_user!

  # POST /events/:event_id/participation
  def create
    @event = Event.find(params[:event_id])

    Event.transaction do
      @event.lock!
      existing = @event.participations.find_by(user_id: current_user.id)
      unless existing
        status, position = next_slot_for(@event)
        @event.participations.create!(user: current_user, status: status, position: position)
      end
    end

    broadcast_event_updates(@event)
    redirect_to event_path(@event)
  end

  # DELETE /events/:event_id/participation
  def destroy
    @event = Event.find(params[:event_id])
    promoted = nil

    Event.transaction do
      @event.lock!
      participation = @event.participations.active.find_by(user_id: current_user.id)
      if participation
        was_confirmed = participation.confirmed?
        participation.update!(status: :cancelled)
        promoted = promote_from_waitlist(@event) if was_confirmed
      end
    end

    if promoted
      PromotionMailer.with(participation: promoted).notify.deliver_later
      WebPushNotifier.perform_later(:promotion, participation_id: promoted.id)
    end
    broadcast_event_updates(@event)
    redirect_to event_path(@event)
  end

  private

  def broadcast_event_updates(event)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ event, :roster ],
      target: dom_id(event, :roster),
      partial: "events/roster",
      locals: { event: event.reload }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      [ event, :counts ],
      target: dom_id(event, :counts),
      partial: "events/counts",
      locals: { event: event.reload }
    )
  end

  def dom_id(*args)
    ActionView::RecordIdentifier.dom_id(*args)
  end

  def next_slot_for(event)
    if event.participations.confirmed.count < event.capacity
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
