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

    redirect_to event_path(@event)
  end

  # DELETE /events/:event_id/participation
  def destroy
    @event = Event.find(params[:event_id])

    Event.transaction do
      @event.lock!
      participation = @event.participations.active.find_by(user_id: current_user.id)
      if participation
        was_confirmed = participation.confirmed?
        participation.update!(status: :cancelled)
        promote_from_waitlist(@event) if was_confirmed
      end
    end

    redirect_to event_path(@event)
  end

  private

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
    # Waitlist/promotion wiring added in M5
  end
end
