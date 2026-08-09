class CalendarFeedsController < ActionController::Base
  def show
    user = User.find_by(calendar_token: params[:token])

    return head :not_found unless user

    events = upcoming_events_for(user)

    send_data EventIcsBuilder.build(events, calendar_name: "Gig Coordinator - #{user.first_name}"),
      type: "text/calendar; charset=UTF-8",
      disposition: %(inline; filename="chicken-catchers-#{user.id}.ics"),
      filename: nil
  end

  private

  def upcoming_events_for(user)
    Event.includes(:host)
      .joins(:participations)
      .where(participations: { user_id: user.id, status: %i[confirmed reserved] })
      .where("scheduled_at > ?", 7.days.ago)
      .order(:scheduled_at)
  end
end
