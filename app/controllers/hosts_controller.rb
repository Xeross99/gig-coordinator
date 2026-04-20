class HostsController < ApplicationController
  before_action :require_user!

  def index
    @hosts = Host.order(:last_name, :first_name).with_attached_photo
    @upcoming_counts = Event.upcoming.group(:host_id).count
    @manager_counts  = HostManager.group(:host_id).count
  end

  def show
    @host = Host.with_attached_photo.includes(managers: { photo_attachment: :blob }).find(params[:id])
  end
end
