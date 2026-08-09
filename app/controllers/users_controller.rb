class UsersController < ApplicationController
  before_action :require_user!
  before_action :require_admin!, only: %i[new create edit update destroy test_push toggle_disabled]

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
    when @user.mistrz_piora?        then Host.with_attached_photo.order(:last_name, :first_name)
    when @user.kurnikowy_komendant? then @user.managed_hosts.with_attached_photo
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

    total_seconds = past_confirmed.sum { |p| p.event.ends_at - p.event.scheduled_at }
    @stats_total_hours = (total_seconds / 3600.0).round

    host_counts = past_confirmed.each_with_object(Hash.new(0)) { |p, h| h[p.event.host_id] += 1 }
    top_ids_with_counts = host_counts.sort_by { |_, c| -c }.first(3)
    hosts_by_id = Host.with_attached_photo.where(id: top_ids_with_counts.map(&:first)).index_by(&:id)
    @top_hosts = top_ids_with_counts.map { |id, count| [ hosts_by_id[id], count ] }
  end

  # POST /pracownicy/:id/testowy-push — admin wysyła userowi testowe
  # powiadomienie (ten sam kind :test co self-test z profilu). Przydatne do
  # diagnozy „nie dostaję powiadomień" bez dostępu do telefonu usera.
  # POST /pracownicy/:id/przelacz-konto — admin wyłącza/włącza konto.
  # Wyłączony user: zero powiadomień (push + mail), zero auto-rezerwacji,
  # brak możliwości zalogowania (sesje ubite, kod logowania nie wychodzi).
  # Dane i historia zostają — to bezpieczniejsza alternatywa dla usunięcia.
  def toggle_disabled
    user = User.find(params[:id])
    if user == Current.user
      redirect_to user_path(user), alert: "Nie możesz wyłączyć własnego konta." and return
    end

    if user.disabled?
      user.enable!
      redirect_to user_path(user), notice: "Konto #{user.display_name} zostało włączone ponownie."
    else
      user.disable!
      redirect_to user_path(user), notice: "Konto #{user.display_name} zostało wyłączone. Nie dostanie już powiadomień ani rezerwacji i nie zaloguje się."
    end
  end

  def test_push
    user = User.find(params[:id])
    if user.disabled?
      redirect_to user_path(user), alert: "Konto jest wyłączone - powiadomienia do tego pracownika nie są wysyłane." and return
    end
    if user.push_subscriptions.exists?
      WebPushNotifier.perform_later(:test, user_id: user.id)
      redirect_to user_path(user), notice: "Wysłano testowe powiadomienie do #{user.display_name}. Powinno przyjść za chwilę."
    else
      redirect_to user_path(user), alert: "Ten pracownik nie ma żadnej subskrypcji push - powiadomienie nie miałoby gdzie dotrzeć."
    end
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to user_path(@user), notice: "Dodano pracownika."
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
      redirect_to user_path(@user), notice: "Zapisano zmiany."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @user = User.find(params[:id])
    if @user == Current.user
      redirect_to user_path(@user), alert: "Nie możesz usunąć własnego konta." and return
    end
    @user.destroy
    redirect_to users_path, notice: "Usunięto pracownika."
  end

  private

  # Mistrz Pióra nie podlega blokadom — jeśli tytuł po zapisie będzie `mistrz_piora`,
  # ignorujemy `blocked_host_ids`. Walidacja `HostBlock#user_is_not_mistrz_piora`
  # blokowałaby save anyway; tu tylko zdejmujemy payload, żeby zapis przeszedł
  # bez „niewidzialnego" błędu dla admina.
  def user_params
    attrs = params.expect(user: [ :first_name, :last_name, :email, :phone, :title, :photo, :can_drive, :premium,
                                  { managed_host_ids: [], blocked_host_ids: [] } ])
    final_title = attrs[:title].presence || @user&.title.to_s
    attrs[:blocked_host_ids] = [] if final_title == "mistrz_piora"
    attrs
  end
end
