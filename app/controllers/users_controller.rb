class UsersController < ApplicationController
  before_action :require_user!

  def index
    # Ranking: master (4) → captain (3) → veteran (2) → member (1) → rookie (0).
    @users = User.order(title: :desc, last_name: :asc, first_name: :asc).with_attached_photo

    # „Na ilu łapaniach był" — confirmed participations na eventach już zakończonych.
    @catch_counts = Participation.confirmed
      .joins(:event)
      .where.not(events: { completed_at: nil })
      .group(:user_id)
      .count
  end

  def show
    @user = User.with_attached_photo.find(params[:id])

    # Mistrz pióra „zarządza" wszystkimi hostami (może im tworzyć eventy),
    # komendant — tylko tymi, z którymi jest jawnie spięty, reszta — żadnymi.
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
end
