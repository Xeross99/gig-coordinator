class EventsController < ApplicationController
  before_action :require_user!

  def index
    @events = Event.upcoming.includes(:host)
    @events = @events.where(host_id: params[:host_id]) if params[:host_id].present?
    @hosts = Host.order(:last_name, :first_name)
    @selected_host_id = params[:host_id].presence&.to_i
  end

  def show
    @event = Event.includes(:host).find(params[:id])
    @host  = @event.host
  end
end
