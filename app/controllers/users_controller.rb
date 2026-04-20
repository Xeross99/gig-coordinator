class UsersController < ApplicationController
  before_action :require_user!
  before_action :require_admin!, only: %i[new create edit update]

  def index
    @users = User.order(title: :desc, last_name: :asc, first_name: :asc).with_attached_photo
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
    params.expect(user: %i[first_name last_name email title photo])
  end
end
