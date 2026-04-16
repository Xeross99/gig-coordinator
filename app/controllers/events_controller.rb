class EventsController < ApplicationController
  before_action :require_user!

  def index
    @events = Event.none # placeholder until M3
    render html: "", layout: true
  end

  def show
    @event = Event.find(params[:id])
  end
end
