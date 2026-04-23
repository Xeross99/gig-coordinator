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

    base = @user.participations.joins(:event).includes(event: :host)
    past_confirmed = base.confirmed
                         .where.not(events: { completed_at: nil })
                         .order("events.scheduled_at DESC")
                         .to_a
    @upcoming = base.active
                    .where(events: { completed_at: nil })
                    .where("events.scheduled_at >= ?", Time.current)
                    .order("events.scheduled_at DESC")
                    .to_a
    @catches_count = past_confirmed.size

    past_cancelled_count = @user.participations.cancelled.joins(:event)
                                .where.not(events: { completed_at: nil }).count
    total_past = past_confirmed.size + past_cancelled_count
    @stats_attendance_pct = total_past.zero? ? nil : (past_confirmed.size * 100.0 / total_past).round
    total_seconds = past_confirmed.sum { |p| p.event.ends_at - p.event.scheduled_at }
    @stats_total_hours = (total_seconds / 3600.0).round

    host_counts = past_confirmed.each_with_object(Hash.new(0)) { |p, h| h[p.event.host_id] += 1 }
    top_ids_with_counts = host_counts.sort_by { |_, c| -c }.first(3)
    hosts_by_id = Host.with_attached_photo.where(id: top_ids_with_counts.map(&:first)).index_by(&:id)
    @top_hosts = top_ids_with_counts.map { |id, count| [hosts_by_id[id], count] }
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
    attrs = params.expect(user: [ :first_name, :last_name, :email, :phone, :title, :photo, :can_drive,
                                  { managed_host_ids: [], blocked_host_ids: [] } ])
    final_title = attrs[:title].presence || @user&.title.to_s
    attrs[:blocked_host_ids] = [] if final_title == "master"
    attrs
  end
end
