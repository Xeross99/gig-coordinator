class HostsController < ApplicationController
  before_action :require_user!
  before_action :require_admin!, only: %i[new create edit update]

  SORTS = {
    "name_asc"  => { first_name: :asc,  last_name: :asc },
    "name_desc" => { first_name: :desc, last_name: :desc }
  }.freeze

  def index
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "name_asc"
    @hosts = Host.order(SORTS.fetch(@sort)).with_attached_photo
    @upcoming_counts = Event.upcoming.group(:host_id).count
    @manager_counts  = HostManager.group(:host_id).count
    @blocked_counts  = HostBlock.group(:host_id).count
  end

  def show
    @host = Host.with_attached_photo
                .includes(managers:       { photo_attachment: :blob },
                          blocked_users:  { photo_attachment: :blob })
                .find(params[:id])
    @upcoming_events = @host.events.upcoming.order(:scheduled_at)
  end

  def new
    @host = Host.new
  end

  def create
    @host = Host.new(host_params)
    if @host.save
      redirect_to host_path(@host), notice: I18n.t("admin.hosts.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @host = Host.find(params[:id])
  end

  def update
    @host = Host.find(params[:id])
    if @host.update(host_params)
      redirect_to host_path(@host), notice: I18n.t("admin.hosts.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def host_params
    params.expect(host: %i[first_name last_name email phone location photo])
  end
end
