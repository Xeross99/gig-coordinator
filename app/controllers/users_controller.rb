class UsersController < ApplicationController
  before_action :require_user!
  before_action :require_admin!, only: %i[new create edit update]

  SORTS = {
    "rank"      => { title: :desc, id: :asc },
    "name_asc"  => { first_name: :asc,  last_name: :asc },
    "name_desc" => { first_name: :desc, last_name: :desc }
  }.freeze

  def index
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "rank"
    @users = User.order(SORTS.fetch(@sort)).with_attached_photo
    @catch_counts = Participation.confirmed
      .joins(:event)
      .where.not(events: { completed_at: nil })
      .group(:user_id)
      .count
  end

  def show
    @user = User.with_attached_photo.find(params[:id])

    @managed_hosts = case
    when @user.master?        then Host.with_attached_photo.order(:last_name, :first_name)
    when @user.captain? then @user.managed_hosts.with_attached_photo
    else                                 Host.none
    end
    @blocked_hosts = @user.blocked_hosts.with_attached_photo

    scope = @user.participations.includes(event: :host).order("events.scheduled_at DESC")
    @past_confirmed = scope.confirmed.select { |p| p.event.completed? }
    @upcoming       = scope.active.reject  { |p| p.event.completed? || p.event.scheduled_at < Time.current }
    @catches_count  = @past_confirmed.size
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to user_path(@user), notice: I18n.t("admin.users.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    if @user.update(user_params)
      redirect_to user_path(@user), notice: I18n.t("admin.users.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def user_params
    params.expect(user: %i[first_name last_name email phone title photo])
  end
end
