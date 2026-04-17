class HostsController < ApplicationController
  before_action :require_user!

  def index
    @hosts = Host.order(:last_name, :first_name).with_attached_photo
    @upcoming_counts = Event.upcoming.group(:host_id).count
  end
end
