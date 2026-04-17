class UsersController < ApplicationController
  before_action :require_user!

  def index
    # Ranking: master (3) → veteran (2) → member (1) → rookie (0).
    @users = User.order(title: :desc, last_name: :asc, first_name: :asc).with_attached_photo

    # „Na ilu łapaniach był" — confirmed participations na eventach już zakończonych.
    @catch_counts = Participation.confirmed
      .joins(:event)
      .where.not(events: { completed_at: nil })
      .group(:user_id)
      .count
  end
end
