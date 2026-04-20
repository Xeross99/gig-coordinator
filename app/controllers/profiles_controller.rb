class ProfilesController < ApplicationController
  before_action :require_user!

  def edit
    @user = Current.user
    sessions = Current.user.sessions.order(created_at: :desc).to_a
    current = sessions.find { |s| s.id == Current.session.id }
    @sessions = current ? [ current, *(sessions - [ current ]) ] : sessions
  end

  def update
    @user = Current.user
    if @user.update(profile_params)
      redirect_to edit_profile_path, notice: "Zapisano"
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def profile_params
    params.expect(user: %i[photo])
  end
end
