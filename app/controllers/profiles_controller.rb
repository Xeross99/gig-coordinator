class ProfilesController < ApplicationController
  before_action :set_user
  # Lista sesji jest ładowana filtrem, a nie w akcji `edit`, bo `update`
  # renderuje ten sam widok przy nieudanej walidacji. Gdy siedziała w akcji,
  # taki render trafiał na `@sessions == nil` i wywalał się na `.each`
  # zamiast pokazać błąd formularza.
  before_action :set_sessions, only: %i[edit update]

  def edit; end

  def update
    if @user.update(profile_params)
      redirect_to edit_profile_path, notice: "Zapisano"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def regenerate_calendar_token
    @user.regenerate_calendar_token!

    redirect_to edit_profile_path, notice: "Wygenerowano nowy URL kalendarza. Stary adres przestanie się synchronizować."
  end

  private

  def profile_params
    permitted = %i[photo]
    permitted << :player_card if Current.user.premium?

    params.expect(user: permitted)
  end

  def set_user
    @user = Current.user
  end

  # Bieżąca sesja na górze listy, reszta od ostatnio widzianej.
  def set_sessions
    sessions = @user.sessions.to_a.sort_by { |s| -(s.last_seen_at || s.created_at).to_i }
    current  = sessions.find { |s| s.id == Current.session.id }
    @sessions = current ? [ current, *(sessions - [ current ]) ] : sessions
  end
end
