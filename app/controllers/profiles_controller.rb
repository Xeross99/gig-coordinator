class ProfilesController < ApplicationController
  before_action :require_user!

  def edit
    @user = current_user
    sessions = current_user.sessions.order(created_at: :desc).to_a
    current = sessions.find { |s| s.id == current_session.id }
    @sessions = current ? [ current, *(sessions - [ current ]) ] : sessions
  end

  def update
    @user = current_user
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
