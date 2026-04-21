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

  # GET /pracownicy/prompt
  # Endpoint dla Lexxy `<lexxy-prompt>` — zwraca listę `<lexxy-prompt-item>`
  # dla @mentions w czacie. Bez layoutu, bez breadcrumbów — tylko sam markup
  # promptu.
  def prompt
    @users = User.order(:first_name, :last_name)
    render layout: false
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

  # Mistrz nie podlega blokadom — jeśli tytuł po zapisie będzie `master`,
  # ignorujemy `blocked_host_ids`. Walidacja `HostBlock#user_is_not_master`
  # blokowałaby save anyway; tu tylko zdejmujemy payload, żeby zapis przeszedł
  # bez „niewidzialnego" błędu dla admina.
  def user_params
    attrs = params.expect(user: [ :first_name, :last_name, :email, :phone, :title, :photo,
                                  { managed_host_ids: [], blocked_host_ids: [] } ])
    final_title = attrs[:title].presence || @user&.title.to_s
    attrs[:blocked_host_ids] = [] if final_title == "master"
    attrs
  end
end
