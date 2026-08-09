class ProfilesController < ApplicationController
  before_action :require_user!

  def edit
    @user = Current.user
    sessions = Current.user.sessions.to_a.sort_by { |s| -(s.last_seen_at || s.created_at).to_i }
    current = sessions.find { |s| s.id == Current.session.id }
    @sessions = current ? [ current, *(sessions - [ current ]) ] : sessions
  end

  def update
    @user = Current.user
    # „Zapisz zdjęcie" bez wybranego pliku wysyła formularz bez klucza `user`
    # w ogóle — ukryty input `user[photo]` jest `disabled`, dopóki DirectUpload
    # go nie wypełni. To nie błąd serwera, tylko pusty submit.
    if profile_params.blank?
      redirect_to edit_profile_path, alert: "Najpierw wybierz zdjęcie." and return
    end

    if @user.update(profile_params)
      redirect_to edit_profile_path, notice: "Zapisano"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def regenerate_calendar_token
    Current.user.regenerate_calendar_token!
    redirect_to edit_profile_path, notice: "Wygenerowano nowy URL kalendarza. Stary adres przestanie się synchronizować."
  end

  private

  # `player_card` przechodzi tylko dla kont premium — nie-premium może
  # aktualizować wyłącznie zdjęcie, spreparowany parametr karty jest ucinany
  # (drugą linią obrony jest `User#clear_player_card_unless_premium`).
  def profile_params
    permitted = %i[photo]
    permitted << :player_card if Current.user.premium?
    params.expect(user: permitted)
  rescue ActionController::ParameterMissing
    {}
  end
end
